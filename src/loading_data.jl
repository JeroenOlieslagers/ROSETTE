function load_raw_data()
    df = CSV.read("data/all_subjects.csv", DataFrame)
    return df
end

"""
    filter_subjects(df)

Remove subjects according to excludion criteria
"""
function filter_subjects(df)
    # New data object
    filtered_data = DataFrame()
    # Count how many subjects get rejected
    counter = 0
    for subject in unique(df.subject)
        # Get problem sets
        subj_data = df[df.subject .== subject, :]
        probs = subj_data.instance
        uniq = unique(probs)
        # Get timestamps
        tt = (subj_data.t)./(1000*60)
        tt .-= first(tt)
        # Get negative time points (BONUS_FAIL/BONUS_SUCCESS)
        negs = findall(x -> x < 0, tt)
        # Remove negative time points
        deleteat!(tt, negs)
        # Calculate intervals between interactions
        intervals = tt[2:end] - tt[1:end-1]
        if (!(last(tt) - first(tt) >= 60 || length(unique(subj_data.instance)) == 70)) || ("win" ∉ subj_data.event)
            counter += 1
            continue
        end
        # Excluse negative interval subjects
        if minimum(intervals) < 0
            counter += 1
            continue
        end
        # Add subject that meets criteria
        filtered_data = vcat(filtered_data, subj_data)
    end
    println("Rejection ratio: " * string(counter) * "/" * string(length(unique(df.subject))))
    return filtered_data
end

"""
    pre_process(df)

Take in DataFrame of subject data, filter it and return DataFrame where colums are 
subject ID, puzzle ID, move, state, distance to goal, difficulty of puzzle, time stamp, attempt
"""
function pre_process(df, d_goals_prbs)
    new_df = DataFrame(subject=String[], puzzle=String[], event=String[], move=a_type[], prev_move=a_type[], s_free=s_free_type[], s_fixed=s_fixed_type[], d_goal=Int[], Lopt=Int[], attempt=Int[], RT=Int[], timestamp=Int[])
    for subj in unique(df.subject)
        subj_df = df[df.subject .== subj .&& df.event .∈ Ref(["start", "restart", "drag_end", "win"]), :]
        for prb in unique(subj_df.instance)
            prb_df = subj_df[subj_df.instance .== prb, :]
            s_free, s_fixed = load_prb_(prb)
            attempt = 0
            prev_t = first(prb_df).t
            prev_move = (0, 0)
            Lopt = parse(Int, prb[end-1] == '_' ? prb[end] : prb[end-1:end]) - 2
            # Don't consider puzzles that are not solved
            if prb_df[end, :event] != "win"
                continue
            end
            for (n, row) in enumerate(eachrow(prb_df))
                # Start of trial / after restart
                d_goal = d_goals_prbs[prb][board_to_int32((s_free, s_fixed))[2]]
                if row.event == "start"
                    attempt += 1
                    if attempt == 1
                        s_free, _ = load_prb_(prb)
                        push!(new_df, [subj, prb, "start", (0, 0), prev_move, copy(s_free), s_fixed, d_goal, Lopt, attempt, row.t - prev_t, row.t])
                    else
                        if last(new_df).event !== "restart" && last(new_df).event !== "start"
                            push!(new_df, [subj, prb, "restart", (0, 0), prev_move, copy(s_free), s_fixed, d_goal, Lopt, attempt-1, row.t - prev_t, row.t])
                        else
                            attempt -= 1
                        end
                        s_free, _ = load_prb_(prb)
                    end
                    prev_t = row.t
                    prev_move = (0, 0)
                    continue
                elseif row.event == "win" || row.event == "restart"
                    continue
                end
                # End if puzzle solved
                if check_solved((s_free, s_fixed))
                    push!(new_df, [subj, prb, "win", (0, 0), prev_move, copy(s_free), s_fixed, d_goal, Lopt, attempt, 0, prev_t])
                    break
                end
                # Skip if car is not moved
                if n < size(prb_df, 1) && prb_df[n+1, :move] == row.move
                    continue
                end
                car_id = row.piece == 8 ? 1 : row.piece + 2
                # Get move amount
                m = 0
                if s_fixed[car_id].dir == :x
                    m = 1 + (row.target % 6) - s_free[car_id]
                else
                    m = 1 + (row.target ÷ 6) - s_free[car_id]
                end
                move = (car_id, m)
                push!(new_df, [subj, prb, "move", move, prev_move, copy(s_free), s_fixed, d_goal, Lopt, attempt, row.t - prev_t, row.t])
                make_move!(s_free, move)
                prev_t = row.t
                prev_move = move
            end
        end
    end
    new_df.first_move = circshift(new_df.event .== "start", 1)
    return new_df
end

function get_filtered_df(subjects, problems, df)
    # filter out trials that did not end in a win
    filtered_df = DataFrame()
    for subj in subjects
        for prb in problems
            df_ = df[df.subject .== subj .&& df.puzzle .== prb, :]
            dummy = DataFrame()
            for row in eachrow(df_)
                if row.event == "start"
                    dummy = DataFrame()
                elseif row.event == "move"
                    push!(dummy, row)
                elseif row.event == "restart"
                    dummy = DataFrame()
                elseif row.event == "win"
                    filtered_df = vcat(filtered_df, dummy)
                end
            end
        end
    end
    return filtered_df
end

function load_rh_data()
    data = CSV.read("data/rh_data.csv", DataFrame)
    state_actions = Vector{Vector{Vector{Tuple{Int, a_type}}}}[]
    subjects = unique(data.subject)
    problems = String.(unique(data.puzzle)[sortperm([parse(Int, x[end-1] == '_' ? x[end] : x[end-1:end]) for x in unique(data.puzzle)])])
    for i in eachindex(subjects)
        state_actions_subj = Vector{Vector{Tuple{Int, a_type}}}[]
        for j in eachindex(problems)
            subject = subjects[i]
            problem = problems[j]
            df_ = data[data.puzzle .== problem .&& data.subject .== subject, :]
            # get moves after last restart
            idxs = findall(x->x=="restart", df_.event)
            if isempty(idxs)
                idxs = [1]
            end
            df = df_[idxs[end]+1:end-1, :]
            #df = df_[df_.event .== "move", :]
            if isempty(df)
                push!(state_actions_subj, [])
                continue
            end
            if length(unique(df.event)) != 1
                println("Not just moves")
            end
            start_pos, s_fixed = load_prb("$(problems[j])")
            rh = RushHour(get_base(5, 9), start_pos, s_fixed)
            game = rh
            s = start_state(game)
            state_actions_subj_game = Tuple{Int, a_type}[]
            for row in eachrow(df)
                move = row[:move]
                car = parse(Int, split(move, ",")[1][2])
                if split(move, ",")[2][end-2] == '-'
                    amount = -parse(Int, split(move, ",")[2][end-1])
                else
                    amount = parse(Int, split(move, ",")[2][end-1])
                end
                push!(state_actions_subj_game, (s, (car, amount)))
                s = make_move(s, (car, amount), game)
            end
            push!(state_actions_subj_game, (s, (0, 0)))
            push!(state_actions_subj, [state_actions_subj_game])
        end
        push!(state_actions, state_actions_subj)
    end
    return subjects, problems, state_actions
end

function games_to_idx(state_actions, analysis_info)
    state_actions_idx = Vector{Vector{Vector{Tuple{Int, a_type}}}}[[] for _ in eachindex(state_actions)]
    for i in 1:70
        state_to_idx, idx_to_state, game, N_t = analysis_info[i]

        for j in eachindex(state_actions)
            if isempty(state_actions[j][i])
                push!(state_actions_idx[j], [])
                continue
            end
            push!(state_actions_idx[j], [[(state_to_idx[state], a) for (state, a) in state_actions[j][i][k]] for k in eachindex(state_actions[j][i])])
            if state_actions_idx[j][end][1][end][1] < 0
                state_actions_idx[j][end][1][end] = (N_t - state_actions_idx[j][end][1][end][1], state_actions_idx[j][end][1][end][2])
            end
        end
    end
    return state_actions_idx
end

function load_rh_parameters()
    folder = "data/params"
    # nlogγao, nlogγp, α
    params = zeros(42, 3)
    i = 1
    for filename in readdir(folder)
        if filename[1] != '.'
            params[i, :] = load("$folder/$filename")["params"]
            i += 1
        end
    end
    return params
end

function load_all_ps()
    folder = "data/all_ps"
    # nlogγao, nlogγp, α
    all_ps = []
    for filename in readdir(folder)
        if filename[1] != '.'
            println(filename)
            push!(all_ps, load("$folder/$filename")["all_ps"][1:end-1])
        end
    end
    push!(all_ps, [load("$folder/$(readdir(folder)[end])")["all_ps"][end]])
    return reduce(vcat, all_ps)
end
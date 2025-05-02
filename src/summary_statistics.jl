
function X_d_goal(move, row, d_goals)
    return row.d_goal
end

function y_d_goal(move, row, d_goals)
    move_idx = findfirst(x->x==move, row.all_moves)
    sampled_s = row.neighs[move_idx]
    d_goal_next = d_goals[row.puzzle][sampled_s]
    return d_goal_next+1
end

function y_p_in_tree(move, row, d_goals)
    AND_root, AND, OR, parents_moves = row.tree
    return move ∈ keys(parents_moves)
end

function y_p_undo(move, row, d_goals)
    if row.prev_move == (0, 0)
        return 0
    else
        undo_move = (row.prev_move[1], -row.prev_move[2])
        return move == undo_move
    end
end

function y_p_same_car(move, row, d_goals)
    if row.prev_move == (0, 0)
        return 0
    else
        prev_car = row.prev_move[1]
        curr_car = move[1]
        return curr_car == prev_car
    end
end

function y_d_tree(move, row, d_goals)
    AND_root, AND, OR, parents_moves = row.tree
    if move in keys(parents_moves)
        ds = [or_node[1] for or_node in parents_moves[move]]
        return minimum(ds)
    else
        return 1e9
    end
end

function y_d_tree_diff(move, row, d_goals)
    AND_root, AND, OR, parents_moves = row.tree
    all_unique_depths = sort(unique(reduce(vcat, [[or_node[1] for or_node in parents_moves[move]] for move in keys(parents_moves)])))
    diff_depths = all_unique_depths .- all_unique_depths[1]
    if move in keys(parents_moves)
        # look at depths of all possible OR nodes, find their position in unique depths,
        # and let this index the rank
        ranked_ds = [diff_depths[findfirst(x->x==or_node[1], all_unique_depths)] for or_node in parents_moves[move]]
        return minimum(ranked_ds)
    else
        return 1e9
    end
end

function y_p_worse(move, row, d_goals)
    move_idx = findfirst(x->x==move, row.all_moves)
    sampled_s = row.neighs[move_idx]
    d_goal_sampled = d_goals[row.puzzle][sampled_s]
    return d_goal_sampled > row.d_goal
end

function y_p_same(move, row, d_goals)
    move_idx = findfirst(x->x==move, row.all_moves)
    sampled_s = row.neighs[move_idx]
    d_goal_sampled = d_goals[row.puzzle][sampled_s]
    return d_goal_sampled == row.d_goal
end

function y_p_better(move, row, d_goals)
    move_idx = findfirst(x->x==move, row.all_moves)
    sampled_s = row.neighs[move_idx]
    d_goal_sampled = d_goals[row.puzzle][sampled_s]
    return d_goal_sampled < row.d_goal
end

function y_p_in_tree_better(move, row, d_goals)
    if y_p_in_tree(move, row, d_goals) == 0
        return 1e9
    else
        return y_p_better(move, row, d_goals)
    end
end

function y_red_back(move, row, d_goals)
    # back_possible = false
    # for move in row.all_moves
    #     if move[1] == 1 && move[2] < 0
    #         back_possible = true
    #         break
    #     end
    # end
    # if back_possible
    #     return move[1] == 1 && move[2] < 0
    # else
    #     return 1e9
    # end
    return move[1] == 1 && move[2] < 0
end

function calculate_summary_statistics(df, d_goals_prbs; iters=100)
    summary_stats = [X_d_goal, y_d_goal, y_p_in_tree, y_p_undo, y_p_same_car, y_d_tree, y_p_worse, y_p_same, y_p_better, y_red_back, y_d_tree, y_d_tree_diff]
    N_stats = length(summary_stats)
    df_stats = DataFrame(subject=String[], puzzle=String[], model=String[], X_d_goal=Int[], y_d_goal=Float64[], y_p_in_tree=Float64[], y_p_undo=Float64[], y_p_same_car=Float64[], y_d_tree=Float64[], y_p_worse=Float64[], y_p_same=Float64[], y_p_better=Float64[], y_red_back=Float64[], h_d_tree=Int[], h_d_tree_diff=Int[])
    df_ = df[df.event .== "move", :]
    for row in ProgressBar(eachrow(df_))
        # subject data
        s = zeros(N_stats)
        for (n, sum_stat) in enumerate(summary_stats)
            s[n] = sum_stat(row.move, row, d_goals_prbs)
        end
        stats = [row.subject, row.puzzle, "data"]
        push!(df_stats, vcat(stats, s))
        # model simulations
        stats = [row.subject, row.puzzle, "model"]
        ps = row.ps
        s = zeros(N_stats - 2, iters)
        for i in 1:iters
            move = wsample(row.all_moves, ps)
            for (n, sum_stat) in enumerate(summary_stats)
                s[n, i] = sum_stat(move, row, d_goals_prbs)
                if n == N_stats - 2
                    break
                end
            end
        end
        stats = vcat(stats, [mean(ss[ss .< 1e9]) for ss in eachrow(s)])
        # histogram stats
        first_move = wsample(row.all_moves, ps)
        stats = vcat(stats, [summary_stats[end-1](first_move, row, d_goals_prbs), summary_stats[end](first_move, row, d_goals_prbs)])
        push!(df_stats, stats)
    end
    return df_stats
end

function bin_stats(df_stats, independent_var::Symbol; nbins=10, subject_level=false)
    input_column_names = propertynames(df_stats)[4:end]
    output_column_names = Symbol[]
    for n in input_column_names
        push!(output_column_names, Symbol("mean_"*string(n)))
        push!(output_column_names, Symbol("std_"*string(n)))
    end
    final_column_names = Symbol[]
    for n in input_column_names
        push!(final_column_names, Symbol("m_"*string(n)))
        push!(final_column_names, Symbol("sem_"*string(n)))
    end
    binned_stats_subj = []
    for subj in unique(df_stats.subject)
        df_subj = df_stats[df_stats.subject .== subj, :]
        transform!(df_subj, independent_var => (x -> add_bin_number(x; nbins=nbins)) => :bin_number)
        gdf_subj = groupby(df_subj, [:bin_number, :model])
        dummy = combine(gdf_subj, input_column_names => calculate_mean_sem_1 => output_column_names)
        dummy[!, :subject] .= subj
        push!(binned_stats_subj, dummy)
    end
    binned_stats_subj_ = vcat(binned_stats_subj...)
    if subject_level
        return binned_stats_subj_
    end
    gdf_binned_stats = groupby(binned_stats_subj_, [:model, :bin_number])
    return combine(gdf_binned_stats, output_column_names => calculate_mean_sem_2 => final_column_names)
end

function add_bin_number(d_goal; nbins=10)
    bin_n = zeros(Int64, length(d_goal))
    bins = quantile(d_goal, 0:(1/nbins):1)
    if nbins == 2
        bins = [0, 0.5, 1.0]
    end
    for i in 1:nbins
        if i < nbins
            idxs = d_goal .>= bins[i] .&& d_goal .< bins[i+1]
        else
            idxs = d_goal .>= bins[i] .&& d_goal .<= bins[i+1]
        end
        bin_n[idxs] .= i
    end
    return bin_n
end

function calculate_mean_sem_1(cols...)
    ls = []
    for col in cols
        push!(ls, mean(col[col .< 1e9]), sem(col[col .< 1e9]))
    end
    return [Tuple(ls)]
end

function calculate_mean_sem_2(cols...)
    ls = []
    for i in 1:Int(length(cols)/2)
        m = cols[2*i - 1]
        s = cols[2*i]
        push!(ls, mean(m), 1.96*sqrt(sem(m)^2 + mean(s .^ 2)/length(s)))
    end
    return [Tuple(ls)]
end

function get_ss(state_actions)
    return vcat([vcat([[state_actions[k][j][1][i][1] for i in 1:(length(state_actions[k][j][1])-1)] for j in 1:length(state_actions[k]) if length(state_actions[k][j]) > 0]...) for k in eachindex(state_actions)]...);
end

function get_all_ps(n, N, df, analysis_info, params, fitting_infos, subjects, problems)
    start_N = n*N
    end_N = (n+1)*N
    
    println(start_N)
    println(end_N)
    flush(stdout)
    
    all_ps = Vector{Float64}[]
    for (n, row) in enumerate(eachrow(df))
        if n < start_N
            continue
        end
        if n > end_N
            continue
        end
    
        if n % 500 == 0
            println(n)
            flush(stdout)
        end
        
        subj_ind = findfirst(x->x==row.subject, subjects)
        problem_ind = findfirst(x->x==row.puzzle, problems)
    
        state_to_idx, idx_to_state, game, N_t = analysis_info[problem_ind]
        s = state_to_idx[row.s]
        prev_move = row.prev_move
        p, neighs = get_p(params[subj_ind, :], s, prev_move, fitting_infos[problem_ind])
        aligned_p = zeros(length(p))
        for (m, neigh) in enumerate(neighs)
            s_int = idx_to_state[neigh]
            state = int_to_s(s_int, game)
            _, s_int_32 = board_to_int32(state)
            idx = findfirst(x->x==s_int_32, row.neighs)
            aligned_p[idx] = p[m]
        end
        push!(all_ps, aligned_p)
    end
    return all_ps
   #@save "all_ps_$(N).jld2" all_ps
end

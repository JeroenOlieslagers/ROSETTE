
function get_stopping_prob(α, f)
    if !(1 > f > 0)
        throw(DomainError("f must be between 0 and 1"))
    end
    if α == 1.0
        return 0.0
    end
    return f ^ tan(α * π/2)
end

function get_stopping_probabilities!(P::Matrix{Float64}, γp::Float64, α::Float64, root_state::Int, all_sizes::Vector{Int})::Nothing
    V_init = -all_sizes[root_state]
    g = (1 - γp)
    for s in eachindex(all_sizes)
        V = -all_sizes[s]
        diff = V - V_init
        if diff < 0
            f = diff / V
            stopping_prob = get_stopping_prob(α, f)
            P[s, 1] = 0
            P[s, 2] = stopping_prob*g
        else
            P[s, 1] = 0
            P[s, 2] = 0
        end
        P[s, 3] = γp
    end
    return nothing
end


function apply_γp(s_init::Int, γp::Float64, α::Float64, fi::FittingStruct)::Matrix{Float64}
    get_stopping_probabilities!(fi.P, γp, α, s_init, fi.all_sizes)

    sm = 1 .- sum(fi.P, dims=2)
    RR = sm .* fi.R'

    R_win = sum(RR, dims=2)
    _R = hcat(R_win, fi.P)

    B = (I - (sm .* fi.Q'))\_R
    return B
end

function p_s(neighs::Vector{Int64}, p_policy::Vector{Float64}, B::Matrix{Float64})::Vector{Float64}
    N_neighs = length(neighs)
    ps = zeros(N_neighs)
    N_t, _ = size(B)
    # change p_stop if incorporating value of state before stopping
    p_stop_all = 0.0
    for i in 1:N_neighs
        n = neighs[i]
        if n <= N_t
            p_stop = B[n, 4] # 4 is stopping
            p_stop_all += p_policy[i] * p_stop
        end
    end
    p_restart = 0.0
    for i in 1:N_neighs
        n = neighs[i]
        if n <= N_t
            p_lose_tie = B[neighs[i], 3] # 3 is losing
            p_restart += p_policy[i] * p_lose_tie
        end
    end
    if abs(p_restart - 1.0) < 1e-12
        for i in 1:N_neighs
            ps[i] = p_policy[i]
        end
    else
        for i in 1:N_neighs
            n = neighs[i]
            p_stop = 0
            p_lose_tie = 0
            if n <= N_t
                p_stop = B[neighs[i], 4]
                p_lose_tie = B[neighs[i], 3]
            end
            ps[i] = p_policy[i] * (1 - p_stop - p_lose_tie + p_stop_all) / (1 - p_restart)
        end
    end
    return ps
end

function apply_γao(temp_dict::Dict{and_type, Float64}, dict::Dict{and_type, Float64}, γ::Float64)::Nothing
    empty!(temp_dict)
    # updated dict
    for (k, v) in dict
        if v > 0
            temp_dict[k] = v*(1-γ)^k[1]
        end
    end
    # probability of stopping
    temp_dict[(0, (-1, -1))] = 1 - sum(values(temp_dict))
    return nothing
end

function process_dict!(ps, move_dict, all_moves, dict, excl_moves)::Nothing
    # add all possible moves
    N_neigh = 0
    for move in all_moves
        if move == (0, 0)
            break
        end
        N_neigh += 1
        move_dict[move] = 0.0
    end
    # stopping
    move_dict[(-1, -1)] = 0.0
    # cycle
    move_dict[(-2, -2)] = 0.0
    # exclude certain moves (e.g. moving same car)
    p_excl = 0
    for and_node in keys(dict)
        if and_node[2] ∉ excl_moves
            move_dict[and_node[2]] += dict[and_node]
        else
            p_excl += dict[and_node]
        end
    end
    # If exclusion move is reached, treat as cycle
    move_dict[(-2, -2)] += p_excl
    # probabilities without cycle
    Z = 0
    # vectorize move probabilities
    for n in 1:N_neigh
        move = all_moves[n]
        p = move_dict[move]
        ps[n] = p
        Z += p
    end
    Z += move_dict[(-1, -1)]
    # repeating because of cycle
    if Z > 0
        p_cycle = move_dict[(-2, -2)]/Z
        # spread proportionally over all other options
        for n in 1:N_neigh
            ps[n] += ps[n] * p_cycle
        end
        move_dict[(-1, -1)] += move_dict[(-1, -1)] * p_cycle
    else # if only cycles are possible (very rare condition) spread over all
        evenly = move_dict[(-2, -2)]/N_neigh
        for n in 1:N_neigh
            ps[n] += evenly
        end
    end
    # spread stopping probability uniformly
    evenly = move_dict[(-1, -1)]/N_neigh
    for n in 1:N_neigh
        ps[n] += evenly
    end
    return nothing
end

function update_QR_matrices_and_or!(fi::FittingStruct, γao::Float64, prev_move::a_type)::Nothing
    N_a, N_t = size(fi.R)
    # preallocate
    ps = zeros(Float64, 4*9)
    temp_dict = Dict{and_type, Float64}()
    move_dict = Dict{a_type, Float64}()
    same_car_moves = prev_move == (0, 0) ? [(0, 0)] : [(prev_move[1], j) for j in -4:4]
    for s in 1:N_t
        dict = fi.all_dicts[s]
        moves = fi.all_moves[s]
        apply_γao(temp_dict, dict, γao)
        process_dict!(ps, move_dict, moves, temp_dict, same_car_moves)
        idxs = fi.all_idxs[s]
        # update Q and R
        for n in eachindex(idxs)
            neigh = idxs[n]
            if neigh > N_t
                fi.R[neigh - N_t, s] = ps[n]
            else
                fi.Q[neigh, s] = ps[n]
            end
        end
    end
    return nothing
end

function get_ll(θ::Vector{Float64}, s::Int, s_next::Int, prev_move::a_type, fi::FittingStruct)::Float64
    γao, γp, α = θ

    update_QR_matrices_and_or!(fi, γao, prev_move)

    B = apply_γp(s, γp, α, fi)

    N_a, N_t = size(fi.R)
    policy = vcat(fi.Q[:, s].nzval, fi.R[:, s].nzval)
    neighs = vcat(fi.Q[:, s].nzind, N_t .+ fi.R[:, s].nzind)

    p = p_s(neighs, policy, B)
    return log(p[findfirst(==(s_next), neighs)])
end

function get_p(θ::Vector{Float64}, s::Int, prev_move::a_type, fi::FittingStruct)
    nlogγao, nlogγp, α = θ
    γao = 10 ^ (-nlogγao)
    γp = 10 ^ (-nlogγp)
    
    update_QR_matrices_and_or!(fi, γao, prev_move)

    B = apply_γp(s, γp, α, fi)

    N_a, N_t = size(fi.R)
    policy = vcat(fi.Q[:, s].nzval, fi.R[:, s].nzval)
    neighs = vcat(fi.Q[:, s].nzind, N_t .+ fi.R[:, s].nzind)

    return p_s(neighs, policy, B), neighs
end

function get_nll(θ::Vector{Float64}, state_actions, fitting_infos)
    nlogγao, nlogγp, α = θ
    γao = 10 ^ (-nlogγao)
    γp = 10 ^ (-nlogγp)
    θp = [γao, γp, α]
    if γao < 0 || γp < 0 || γao > 1 || γp > 1 || α < 0 || α > 1
        return Inf
    end
    nll = 0.0
    for j in eachindex(state_actions)
        if isempty(state_actions[j])
            continue
        end
        fitting_info = fitting_infos[j]
        for game_index in eachindex(state_actions[j])
            state_actions_game = state_actions[j][game_index]
            a_prev = (0, 0)
            s, a = state_actions_game[1]
            for i in 1:length(state_actions_game)-1
                s_next, a_next = state_actions_game[i+1]

                nll -= get_ll(θp, s, s_next, a_prev, fitting_info)

                a_prev = a
                s = s_next
                a = a_next
            end
        end
    end
    return nll
end

function fit_cluster(n, N, idxs, fitting_infos, state_actions_idx)
    # n = subject index
    # N = number of puzzles to fit
    fi = fitting_infos[idxs[1:N]];
    sa = state_actions_idx[n][idxs[1:N]];

    f = x -> get_nll(x, sa, fi)

    res = optimize(f, [1.0, 1.0, 0.5]; g_tol=0.0001, show_trace=true);
    # params = Optim.minimizer(res)
    # @save "params_$(n).jld2" params
end

function get_fitting_infos(problems)
    fitting_infos = []
    for i in ProgressBar(1:70)
        start_pos, s_fixed = load_prb("$(problems[i])")
        game = RushHour(get_base(5, 9), start_pos, s_fixed)

        state_to_idx, idx_to_state, Q, R = get_QR_matrices(game)
        N_a, N_t = size(R)

        all_dicts, all_moves, all_idxs, all_sizes = get_and_or_dicts(N_t, idx_to_state, state_to_idx, game)

        P = zeros(length(all_sizes), 3)

        fitting_info = FittingStruct(all_dicts, all_moves, all_idxs, Q, R, P, all_sizes);
        push!(fitting_infos, fitting_info)
    end
    return fitting_infos
end

function get_analysis_info(problems)
    analysis_info = []
    for prb in problems
        start_pos, s_fixed = load_prb("$(prb)")
        game = RushHour(get_base(5, 9), start_pos, s_fixed)

        state_to_idx, idx_to_state, Q, R = get_QR_matrices(game)
        #states, leafs, V, state_to_idx, idx_to_state, win_lose_tie, first_player, Q, R, Vstar
        push!(analysis_info, (state_to_idx, idx_to_state, game, size(R)[2]))
    end
    return analysis_info
end

function get_QR_matrices(game::RushHour)
    states, leafs = search(game)
    N_t = length(states)
    N_a = length(leafs)
    # transient to transient state transition matrix
    Q = sparse(zeros(N_t, N_t))
    # transient to absorbing state transition matrix
    R = sparse(zeros(N_a, N_t))
    # converting states to indices and back
    state_to_idx = Dict{Int, Int}()
    idx_to_state = zeros(Int, N_t + N_a)
    for (n, s_int) in enumerate(states)
        state_to_idx[s_int] = n
        idx_to_state[n] = s_int
    end
    # leaf nodes have negative indices
    for (n, s_int) in enumerate(leafs)
        state_to_idx[s_int] = -n
        idx_to_state[N_t + n] = s_int
    end
    # populate Q and R matrices, using a uniformly random policy
    for s in states
        from = state_to_idx[s]
        neighs = neighbours(s, game)
        for (n, neigh) in enumerate(neighs)
            to = state_to_idx[neigh]
            if neigh in leafs
                R[-to, from] = 1.0 / length(neighs)
            elseif neigh in states
                Q[to, from] = 1.0 / length(neighs)
            else
                error("state not found")
            end
        end
    end
    return state_to_idx, idx_to_state, Q, R
end

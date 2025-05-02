
function get_and_or_tree(s::s_type; max_iter=100)
    # keeps track of current train of thought nodes visited
    train_of_thought = Vector{subgoal_type}()
    # keeps track of parents of leaf nodes
    parents_moves = DefaultDict{a_type, Vector{and_type}}([])
    # forward pass (children)
    AND = DefaultDict{and_type, Vector{or_type}}([])
    OR = DefaultDict{or_type, Vector{and_type}}([])
    # initialize process
    arr = zeros(Int, 6, 6)
    board_to_arr!(arr, s)
    s_free, s_fixed = s
    # ultimate goal move
    m_init = 6 - (s_free[1]+1)
    root_move = (1, m_init)
    first_thought = MVector{5, Int}(1, m_init, 0, 0, 0)
    push!(train_of_thought, first_thought)
    # Root OR
    OR_root = (1, first_thought)
    # Root AND
    AND_root = (1, root_move)
    push!(OR[OR_root], AND_root)
    # Get first child nodes
    blocked_cars = zeros(blocked_cars_type)
    move_amounts = zeros(move_amounts_type)
    blocking_nodes = zeros(Int, 4, 5)
    get_blocking_nodes!(blocking_nodes, blocked_cars, move_amounts, s, arr, root_move)
    # all possible moves from start position
    moves = @MVector([(0, 0) for _ in 1:(4*9)])
    possible_moves!(moves, s, arr)
    # Tree with all info
    AND_OR_tree = [AND_root, AND, OR, parents_moves]
    # Expand tree and recurse
    add_to_tree!(AND_root, blocking_nodes, blocked_cars, move_amounts, train_of_thought, moves, AND_OR_tree, s, arr, 0; max_iter=max_iter)
    if isempty(AND)
        leaf = (1, zeros(subgoal_type))
        push!(AND[AND_root], leaf)
    end
    AND_root, AND, OR, parents_moves = AND_OR_tree
    AND_OR_tree = [AND_root, Dict(AND), Dict(OR), Dict(parents_moves)]
    return AND_OR_tree
end

function add_to_tree!(prev_AND::and_type, blocking_nodes::blocking_nodes_type, blocked_cars::blocked_cars_type, move_amounts::move_amounts_type, train_of_thought::Vector{subgoal_type}, moves::moves_type, AND_OR_tree, s::s_type, arr::arr_type, recursion_depth::Int; max_iter=100)::Nothing
    AND_root, AND, OR, parents_moves = AND_OR_tree
    if recursion_depth > max_iter
        throw(DomainError("max_iter depth reached"))
        return nothing
    end
    d, move = prev_AND
    # recurse all children
    for node in eachrow(blocking_nodes)
        if node[1] == 0
            break
        end
        or_node = (d+1, node)
        if or_node ∉ AND[prev_AND]
            push!(AND[prev_AND], or_node)
        end
        if node in train_of_thought
            continue
        end
        # loop over next set of OR nodes
        for j in 2:lastindex(node)
            if node[j] == 0
                break
            end
            next_move = (node[1], node[j])

            new_blocking_nodes = copy(blocking_nodes)
            get_blocking_nodes!(new_blocking_nodes, blocked_cars, move_amounts, s, arr, next_move)
            # move is impossible
            if new_blocking_nodes[1, 1] == -1
                continue
            end

            and_node = (d+1, next_move)
            if and_node ∉ OR[or_node]
                push!(OR[or_node], and_node)
            end

            if new_blocking_nodes[1, 1] == 0
                leaf = (d+1, zeros(subgoal_type))
                if leaf ∉ AND[and_node]
                    push!(AND[and_node], leaf)
                end
                if and_node ∉ parents_moves[next_move]
                    push!(parents_moves[next_move], and_node)
                end
                continue
            end
            # we copy because we dont want the same nodes in a chain,
            # but across same chain (at different depths) we can have the same node repeat
            new_train_of_thought = copy(train_of_thought)
            push!(new_train_of_thought, node)
            add_to_tree!(and_node, new_blocking_nodes, blocked_cars, move_amounts, new_train_of_thought, moves, AND_OR_tree, s, arr, recursion_depth + 1; max_iter=max_iter)
        end
    end
    return nothing
end

function get_blocking_nodes!(blocking_nodes::blocking_nodes_type, blocked_cars::blocked_cars_type, move_amounts::move_amounts_type, s::s_type, arr::arr_type, move::a_type)::Nothing
    fill!(blocking_nodes, 0)
    # get all blocking cars
    move_blocked_by!(blocked_cars, move, s, arr)
    for i in eachindex(blocked_cars)
        # Get all OR nodes of next layer
        id2 = blocked_cars[i]
        if id2 == 0
            break
        end
        unblocking_moves!(move_amounts, move, id2, s)
        # If no possible moves, end iteration for this move
        if sum(move_amounts) == 0
            fill!(blocking_nodes, -1)
            break
        end
        # new ao state
        blocking_nodes[i, 1] = id2
        for j in eachindex(move_amounts)
            blocking_nodes[i, j+1] = move_amounts[j]
        end
    end
    return nothing
end

function propagate_ps(x::Float64, AND_OR_tree)::Dict{and_type, Float64}
    function propagate!(x::Float64, p::Float64, train_of_thought, dict, AND_current::and_type, AND, OR)::Nothing
        γ = x
        # number of children of OR node
        N_or = length(AND[AND_current])
        # Rule 2: OR HEURISTICS
        p_ors = p * ones(N_or) / N_or
        # propagate to AND nodes
        for (n, OR_node) in enumerate(AND[AND_current])
            p_or = p_ors[n]
            # CYCLE PROBABILITY
            if OR_node[2] in train_of_thought || OR_node ∉ keys(OR)
                dict[(OR_node[1], (-2, -2))] += (1-γ)*p_or
                dict[(OR_node[1], (-1, -1))] += γ*p_or
                continue
            end
            push!(train_of_thought, OR_node[2])
            # Rule 1a: don't stop
            pp = (1-γ)*p_or
            # Rule 1b: stop
            dict[(OR_node[1], (-1, -1))] += γ*p_or
            N_and = length(OR[OR_node])
            # Rule 3: AND HEURISTICS
            p_ands = pp * ones(N_and) / N_and
            # propagate to AND nodes
            for (m, AND_next) in enumerate(OR[OR_node])
                p_and = p_ands[m]
                # leaf node
                if AND[AND_next][1][2][1] == 0
                    dict[AND_next] += p_and
                else
                    # train of thought
                    new_train_of_thought = copy(train_of_thought)
                    # recurse
                    propagate!(x, p_and, new_train_of_thought, dict, AND_next, AND, OR)
                end
            end
        end
        return nothing
    end
    AND_root, AND, OR, parents_moves = AND_OR_tree
    dict = DefaultDict{and_type, Float64}(0.0)
    dict[(1, (-1, -1))] = x
    if length(AND) == length(OR) == 1
        dict[(1, AND_root[2])] = 1 - x
    else
        # keeps track of current train of thought nodes visited
        train_of_thought = Vector{subgoal_type}()
        push!(train_of_thought, MVector{5, Int}([AND_root[2][1], AND_root[2][2], 0, 0, 0]))
        propagate!(x, 1 - x, train_of_thought, dict, AND_root, AND, OR)
    end
    return Dict(dict)
end

function get_and_or_dicts(N_t::Int, idx_to_state, state_to_idx, game::RushHour)
    all_dicts = Dict{Tuple{Int64, Tuple{Int64, Int64}}, Float64}[]
    all_moves = MVector{36, Tuple{Int64, Int64}}[]
    all_idxs = Vector{Int64}[]
    all_sizes = Int64[]
    
    arr = zeros(Int, 6, 6)
    moves = @MVector([(0, 0) for _ in 1:(4*9)])
    for s_idx in 1:N_t
        s = idx_to_state[s_idx] 
        ss = int_to_s(s, game)
        t = get_and_or_tree(ss)
        d = propagate_ps(0.0, t)
        board_to_arr!(arr, ss)
        possible_moves!(moves, ss, arr)
        idxs = moves_to_idxs(moves, ss, state_to_idx, N_t)
        push!(all_dicts, d)
        push!(all_moves, copy(moves))
        push!(all_idxs, idxs)
        push!(all_sizes, length(t[3]))
    end
    return all_dicts, all_moves, all_idxs, all_sizes
end

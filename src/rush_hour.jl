using JSON

struct Car
    dim2::Int8
    dir::Symbol
    len::Int8
end

struct RushHour
    bs::Vector{Int}
    initial_position::Vector{Int}
    s_fixed::Vector{Car}
end

function load_prb(prb::String)::Tuple{Vector{Int}, Vector{Car}}
    data = JSON.parsefile("data/problems/$prb.json")
    size = length(data["cars"])
    s_free = zeros(Int, size)
    s_fixed = Array{Car}(undef, size)
    for car in data["cars"]
        id = car["id"] != "r" ? parse(Int, car["id"]) + 2 : 1
        x = 1 + car["position"] % 6
        y = 1 + car["position"] ÷ 6
        dir = car["orientation"] == "horizontal" ? :x : :y
        len = car["length"]
        if dir == :x
            s_free[id] = x - 1
            s_fixed[id] = Car(y, dir, len)
        else
            s_free[id] = y - 1
            s_fixed[id] = Car(x, dir, len)
        end
    end
    return s_free, s_fixed
end

function make_move(s::Int, m::Tuple{Int, Int}, game::RushHour)::Int
    piece, amount = m
    return s + amount*game.bs[piece]
end

function neighbours(s::Int, game::RushHour)::Vector{Int}
    ns = Int[]
    arr = draw_state(s, game)
    for i in 1:9
        car = game.s_fixed[i]
        dim1 = check_digit(s, i, game)+1
        # backward moves
        for (n, j) in enumerate(reverse(1:dim1-1))
            if car.dir == :x
                if arr[car.dim2, j] == 0
                    push!(ns, make_move(s, (i, -n), game))
                else
                    break
                end
            else
                if arr[j, car.dim2] == 0
                    push!(ns, make_move(s, (i, -n), game))
                else
                    break
                end
            end
        end
        # forward moves
        for (n, j) in enumerate(dim1+car.len:6)
            if car.dir == :x
                if arr[car.dim2, j] == 0
                    push!(ns, make_move(s, (i, n), game))
                else
                    break
                end
            else
                if arr[j, car.dim2] == 0
                    push!(ns, make_move(s, (i, n), game))
                else
                    break
                end
            end
        end
    end
    return ns
end

function get_all_moves(s::Int, game::RushHour)::Vector{Tuple{Int, Int}}
    moves = Tuple{Int, Int}[]
    arr = draw_state(s, game)
    for i in 1:9
        car = game.s_fixed[i]
        dim1 = check_digit(s, i, game)+1
        # backward moves
        for (n, j) in enumerate(reverse(1:dim1-1))
            if car.dir == :x
                if arr[car.dim2, j] == 0
                    push!(moves, (i, -n))
                else
                    break
                end
            else
                if arr[j, car.dim2] == 0
                    push!(moves, (i, -n))
                else
                    break
                end
            end
        end
        # forward moves
        for (n, j) in enumerate(dim1+car.len:6)
            if car.dir == :x
                if arr[car.dim2, j] == 0
                    push!(moves, (i, n))
                else
                    break
                end
            else
                if arr[j, car.dim2] == 0
                    push!(moves, (i, n))
                else
                    break
                end
            end
        end
    end
    return moves
end

function has_won(s::Int, game::RushHour)::Bool
    arr = draw_state(s, game)
    if check_digit(s, 1, game) == 4
        return true
    elseif unique(arr[3, check_digit(s, 1, game)+3:6]) == [0]
        return true
    else
        return false
    end
    # THIS INCLUDES THE FINAL MOVE AS REQUIRED TO WIN
    # return check_digit(s, 1, game) == 4
end

function has_lost(s::Int, game::RushHour)::Bool
    return false
end

function draw_state(s::Int, game::RushHour)::Matrix{Int}
    arr = zeros(Int, 6, 6)
    for id in eachindex(game.s_fixed)
        car = game.s_fixed[id]
        dim1 = check_digit(s, id, game)+1
        if car.dir == :x
            for i in 0:car.len-1
                arr[car.dim2, dim1+i] = id
            end
        else
            for i in 0:car.len-1
                arr[dim1+i, car.dim2] = id
            end
        end
    end
    return arr
end

function get_base(base::Int, n::Int)::Vector{Int}
    return base .^ (0:n-1)
end

function start_state(game::RushHour)::Int
    s = 0
    for (p, v) in enumerate(game.initial_position)
        s += v*game.bs[p]
    end
    return s
end

function check_digit(s::Int, n::Int, game::RushHour)::Int
    return (s ÷ game.bs[n]) % game.bs[2]
end

function is_terminal(s::Int, game::RushHour)::Bool
    # if a two-player game, check if state is not a win, tie, or loss
    return has_won(s, game)
end

function search(game::RushHour; max_iters=100000)
    s_start = start_state(game)
    states = Set{Int}(s_start)
    leafs = Set{Int}()
    frontier = Int[s_start]
    for i in 1:max_iters
        if i % 100000 == 0
            println("Iteration: $i")
        end
        if isempty(frontier)
            return states, leafs
        end
        s = popfirst!(frontier)
        for neigh in neighbours(s, game)
            if neigh in states
                continue
            end
            if is_terminal(neigh, game)
                push!(leafs, neigh)
                continue
            end
            push!(states, neigh)
            push!(frontier, neigh)
        end
    end
    return Set{Int}(), Set{Int}()
    #error("Maximum search depth reached")
end
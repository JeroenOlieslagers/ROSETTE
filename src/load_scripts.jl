# require julia 1.8.5
# require DataFrames v1.3.6
using ProgressBars
using DataStructures
using Plots
using StaticArrays
using DataFrames
using CSV
using JLD2
using Optim
using SparseArrays
using LinearAlgebra
using StatsBase


# FOR FIXED SIZE RUSH HOUR PUZZLES
L = 9
######
s_free_type = MVector{L, Int}
s_fixed_type = NTuple{L, Car}
s_type = Tuple{s_free_type, s_fixed_type}
a_type = Tuple{Int, Int}
arr_type = Matrix{Int}

moves_type = MVector{4*L, a_type}
blocked_cars_type = MVector{4, Int}
move_amounts_type = MVector{4, Int}
blocking_nodes_type = Matrix{Int}

subgoal_type = MVector{5, Int}# (car, moves that unblock)
or_type = Tuple{Int, subgoal_type}# depth, subgoal
and_type = Tuple{Int, a_type}# depth, move

struct FittingStruct
    all_dicts::Vector{Dict{Tuple{Int64, Tuple{Int64, Int64}}, Float64}}
    all_moves::Vector{MVector{36, Tuple{Int64, Int64}}}
    all_idxs::Vector{Vector{Int64}}
    Q::SparseMatrixCSC{Float64, Int64}
    R::SparseMatrixCSC{Float64, Int64}
    P::Matrix{Float64}
    all_sizes::Vector{Int64}
end

include("rush_hour.jl")
include("rush_hour_utils.jl")
include("loading_data.jl")
include("model_fitting.jl")
include("and_or_trees.jl")
include("summary_statistics.jl")
include("plotting.jl")
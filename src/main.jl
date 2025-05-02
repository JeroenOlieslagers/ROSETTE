include("load_scripts.jl")


subjects, problems, state_actions = load_rh_data();

analysis_info = get_analysis_info(problems);
analysis_info = load("data/processed_data/analysis_info.jld2")["analysis_info"];


state_actions_idx = games_to_idx(state_actions, analysis_info);
state_actions_idx = load("data/processed_data/state_actions_idx.jld2")["state_actions_idx"];

fitting_infos = get_fitting_infos(problems)
fitting_infos = load("data/processed_data/fitting_infos.jld2")["fitting_infos"];

idxs = [52, 64, 12, 29, 37, 8, 63, 58, 46, 35, 57, 22, 20, 16, 69, 68, 41, 56, 32, 33, 49, 21, 36, 50, 51, 61, 65, 62, 14, 70, 23, 1, 25, 31, 4, 38, 39, 48, 6, 2, 45, 60, 55, 67, 53, 5, 26, 54, 19, 27, 44, 28, 10, 42, 18, 13, 11, 40, 3, 9, 24, 15, 59, 43, 47, 30, 7, 66, 34, 17];

fit_cluster(1, 2, idxs, fitting_infos, state_actions_idx)


params = load_rh_parameters();



d_goals_prbs = load("data/processed_data/d_goals_prbs.jld2");
df = pre_process(filter_subjects(load_raw_data()), d_goals_prbs);

stuff = load("data/processed_data/stuff.jld2");
df[!, :tree] = stuff["trees"];
df[!, :dict] = stuff["dicts"];
df[!, :all_moves] = stuff["all_moves"];
df[!, :neighs] = stuff["neighs"];
df[!, :features] = stuff["features"];

filtered_df = get_filtered_df(subjects, problems, df);

ss =  get_ss(state_actions);
filtered_df[!, :s] = ss;

get_all_ps(0, 1, filtered_df, analysis_info, params, fitting_infos, subjects, problems);
all_ps = load_all_ps();
filtered_df[!, :ps] = all_ps;


df_stats = calculate_summary_statistics(filtered_df, d_goals_prbs)
binned_stats = bin_stats(df_stats, :X_d_goal)



figA(binned_stats)
figB(df_stats)
figC(binned_stats)
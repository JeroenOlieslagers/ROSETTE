function normalize_hist_counts(df, v1, v2, idv, lims)
    df[!, :norm_counts] = zeros(Float64, size(df, 1))
    for a in unique(df[!, v1])
        for b in unique(df[!, v2])
            dummy = df[df[!, v1] .== a .&& df[!, v2] .== b, :].hist_counts
            df[df[!, v1] .== a .&& df[!, v2] .== b, :norm_counts] .= dummy ./ sum(dummy)
            for d in lims
                df_ = df[df[!, v1] .== a .&& df[!, v2] .== b, :]
                if d ∉ df_[!, idv]
                    push!(df, [a, b, d, 0, 0])
                end
            end
        end
    end
    return df
end

function figA(binned_stats)
    models = ["model"] 
    DVs = ["y_p_in_tree", "y_d_tree", "y_p_undo", "y_p_same_car"]
    IDV = "X_d_goal"
    MM = length(models)
    d = length(DVs)
    l = @layout [grid(1, d); a{0.001h}];
    plot(size=(744, 220), grid=false, layout=l, dpi=300, xflip=true,
        legendfont=font(14, "helvetica"), 
        xtickfont=font(12, "helvetica"), 
        ytickfont=font(12, "helvetica"), 
        titlefont=font(14, "helvetica"), 
        guidefont=font(14, "helvetica"), 
        right_margin=0Plots.mm, top_margin=1Plots.mm, bottom_margin=7Plots.mm, left_margin=5Plots.mm, 
        fontfamily="helvetica", tick_direction=:out, xlim=(0, 16));

    ylabels = ["Prop. sensible" "Depth in tree" "Prop. undos" "Prop. same car"];
    ytickss = [[0.8, 0.85, 0.9, 0.95], [2.0, 3.0, 4.0, 5.0], ([0.0, 0.05, 0.1], ["0", "0.05", "0.1"]), ([0.0, 0.05, 0.1, 0.15], ["0", "0.05", "0.1", "0.15"])]
    ylimss = [(0.75, 0.95), (2, 5), (-Inf, 0.11), (0, 0.15)]
    order = [1, 3]

    for i in 1:d
        for j in 1:MM
            df_data = binned_stats[binned_stats.model .== "data", :]
            df_model = binned_stats[binned_stats.model .== models[j], :]
            sort!(df_data, :bin_number)
            sort!(df_model, :bin_number)
            ylabel = ylabels[i]
            title = ""
            yticks = ytickss[i]
            xticks = [0, 5, 10, 15]
            ylims = ylimss[i]
            sp = i
            o = order[j]

            plot!(df_data[:, "m_"*IDV], df_data[:, "m_"*DVs[i]], yerr=df_data[:, "sem_"*DVs[i]], sp=sp, c=:white, msw=1.4, label=nothing, xflip=true, linewidth=1, markershape=:none, ms=4, ylabel=ylabel, xticks=xticks, yticks=yticks)
            plot!(df_model[:, "m_"*IDV], df_model[:, "m_"*DVs[i]], ribbon=df_model[:, "sem_"*DVs[i]], sp=sp, label=nothing, c=palette(:default)[o], l=nothing, ylabel=ylabel, title=title, xticks=xticks, yticks=yticks, ylims=ylims)
            plot!(df_model[:, "m_"*IDV], df_model[:, "m_"*DVs[i]], ribbon=df_model[:, "sem_"*DVs[i]], sp=sp, label=nothing, c=palette(:default)[o], l=nothing, ylabel=ylabel, title=title, xticks=xticks, yticks=yticks, ylims=ylims)
        end
    end
    plot!(xlabel="Distance to goal", showaxis=false, grid=false, sp=d + 1, top_margin=-15Plots.mm, bottom_margin=7Plots.mm)
    display(plot!())
end

function figB(df_stats)
    models = ["model"]
    Vs = [:h_d_tree, :h_d_tree_diff]
    lims = [2:11, 1:9]
    MM = length(models)
    d = length(Vs)
    l = @layout [grid(1, d)];
    plot(size=(298, 200), grid=false, layout=l, dpi=300, xflip=false,
        legendfont=font(14, "helvetica"), 
        xtickfont=font(12, "helvetica"), 
        ytickfont=font(12, "helvetica"), 
        titlefont=font(14, "helvetica"), 
        guidefont=font(14, "helvetica"), 
        right_margin=0Plots.mm, top_margin=0Plots.mm, bottom_margin=1Plots.mm, left_margin=0Plots.mm, 
        fontfamily="helvetica", tick_direction=:out);

    xlabels = ["Depth" "Delta depth"]
    order = [1, 3]
    ytickss = [([0.0, 0.1, 0.2], ["0", "0.1", "0.2"]), ([0.0, 0.2, 0.4], ["0", "0.2", "0.4"])]
    xtickss = [[2, 4, 6, 8, 10], [0, 2, 4, 6, 8]]
    for i in 1:d
        r = Vs[i]
        df_ = df_stats[df_stats.h_d_tree .< 1000, :]
        gdf = groupby(df_, [:subject, :model, r])
        count_df = combine(gdf, r => length => :hist_counts)
    
        count_df_norm = normalize_hist_counts(count_df, "subject", "model", r, lims[i])
    
        diff_gdf = groupby(count_df_norm, [:model, r])
        diff_df = combine(diff_gdf, :norm_counts => (x -> [(mean(x), sem(x))]) => [:hist_mean, :hist_sem])

        df_data = diff_df[diff_df.model .== "data", :]
        xlabel = xlabels[i]
        ylabel = i == 1 ? "Proportion" : ""
        title = ""
        yticks = ytickss[i]
        xticks = xtickss[i]
        bar!(df_data[:, r], df_data[:, :hist_mean], yerr=1.96*df_data[:, :hist_sem], sp=i, c=:white, msw=1.4, label=nothing, linewidth=1.4, markershape=:none, ms=0, title=title, ylabel=ylabel, xticks=xticks, yticks=yticks, linecolor=:gray, markercolor=:gray, xlabel=xlabel, left_margin=i==1 ? 0Plots.mm : -4Plots.mm)
        for j in 1:MM
            df_model = diff_df[diff_df.model .== models[j], :]
            sort!(df_model, r)
            o = order[j]
            plot!(df_model[:, r], df_model[:, :hist_mean], ribbon=1.96*df_model[:, :hist_sem], sp=i, label=nothing, c=palette(:default)[o], l=nothing)
            plot!(df_model[:, r], df_model[:, :hist_mean], ribbon=1.96*df_model[:, :hist_sem], sp=i, label=nothing, c=palette(:default)[o], l=nothing)
        end
    end
    display(plot!())
end

function figC(binned_stats)
    models = ["data", "model"]
    DVs = ["m_y_p_worse", "m_y_p_same", "m_y_p_better"]
    IDV = "m_X_d_goal"
    MM = length(models)
    d = length(DVs)
    l = @layout [a{0.001h}; grid(1, MM); a{0.001h}];
    plot(size=(446, 200), grid=false, layout=l, dpi=300, xflip=true, link=:both,
        legendfont=font(14, "helvetica"), 
        xtickfont=font(12, "helvetica"), 
        ytickfont=font(12, "helvetica"), 
        titlefont=font(14, "helvetica"), 
        guidefont=font(14, "helvetica"), 
        right_margin=0Plots.mm, top_margin=1Plots.mm, bottom_margin=4Plots.mm, left_margin=0Plots.mm, 
        fontfamily="helvetica", tick_direction=:out, xlim=(0, 15), ylim=(0, 1), yticks=nothing)

    labels = ["Worse   " "Same   " "Better   "]
    bar!([0 0 0], c=[palette(:default)[1] palette(:default)[2] palette(:default)[3]], labels=labels, legend_columns=length(labels), linewidth=0, sp=1, showaxis=false, grid=false, background_color_legend=nothing, foreground_color_legend=nothing, legend=:top, top_margin=-2Plots.mm);
    titles = ["Participants" "Model" "AND-OR"];
    xlabels = ["" "" ""]
    ylabels = ["Proportion" "" ""]
    yticks = [([0, 0.2, 0.4, 0.6, 0.8, 1], ["0", "0.2", "0.4", "0.6", "0.8", "1"]) for _ in 1:MM]
    xticks = [[0, 5, 10, 15] for _ in 1:MM]
    for i in 1:MM
        df_ = binned_stats[binned_stats.model .== models[i], :]
        areaplot!(df_[:, IDV] .- 1, [df_[:, DVs[1]] + df_[:, DVs[2]] + df_[:, DVs[3]], df_[:, DVs[2]] + df_[:, DVs[3]], df_[:, DVs[3]]], sp=i+1, xflip=true, label=nothing, xlabel=xlabels[i], ylabel=ylabels[i], title=titles[i], yticks=yticks[i], xticks=xticks[i], left_margin=i==1 ? 2Plots.mm : -1Plots.mm)    
    end
    plot!(xlabel="Distance to goal", showaxis=false, grid=false, sp=MM+2, top_margin=-12Plots.mm)
    display(plot!())
end
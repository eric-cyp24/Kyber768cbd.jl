
using Printf, HDF5, Statistics, MathTeXEngine#, LaTeXStrings
using Plots, ColorSchemes #mapc, colorschemes
using TemplateAttack: loaddata, success_rate, guessing_entropy


### Parameters ##########
include("Parameters.jl")
TracesDIR = ext1TracesDIROs #joinpath(@__DIR__, "../data/Traces-Os/")
ppc = 20 # sample points per clock 
###

tplidx, tgtidx = :DK1, :DK1
tplDir, tgtDir = DirHPFOs, DirHPFOs
postfix        = "_test_K"
method         = :marginalize

IVs = [:Buf, :XY, :S]
POIe_left_list  = [0,20,40,80,160]
POIe_right_list = [0,20,40,80,160] 
tabletype = :Guessing_Entropy

tickfontsize, guidefontsize, titlefontsize = 20,26,32
OUTDIR  = "results/"
showfig = true
### end of Parameters ###


function getresultfile(;method, TemplateDir, TargetDir, postfix=postfix)
    resultfile = "$(method)_Result_test_POIe_with_Templates_from_$(replace(TemplateDir,"/"=>"_")[1:end-1]).h5"
    OUTDIR     = joinpath(TracesDIR, TargetDir, "lanczos2_25$(postfix)/", "Results/test_POIe/")
    return joinpath(OUTDIR, resultfile)
end

function loadGE(resultfile; iv, POIe_left_list=POIe_left_list, POIe_right_list=POIe_right_list)
    GEtable = Matrix{Float32}(undef, length(POIe_right_list), length(POIe_left_list))
    h5open(resultfile) do h5
        for (i,POIe_left) in enumerate(POIe_left_list)
            for (j,POIe_right) in enumerate(POIe_right_list)
                GEtable[j,i] = mean(read(h5, "Traces_Templates_Unmodified_POIe$(POIe_left)-$(POIe_right)/Guessing_Entropy/$(iv)"))
            end
        end
    end
    return GEtable
end

function plotGE_POIe_3d(GEtables; IVs, POIe_left_list, POIe_right_list, OUTDIR=OUTDIR, show=true)
    GEplots3d, POIe_lefts, POIe_rights = Dict(), POIe_left_list.÷ppc, POIe_right_list.÷ppc
    for iv in IVs
        xlims = (minimum(POIe_lefts),maximum(POIe_lefts))
        ylims = (minimum(POIe_rights),maximum(POIe_rights))
        u,l   = maximum(GEtables[iv]),minimum(GEtables[iv])
        diff  = u - l
        zlims  = (l-0.1*diff, u+0.1*diff) # or :auto
        
        p = wireframe(POIe_lefts, POIe_rights, GEtables[iv]; title=L"GE of $\mathit{%$(iv)}$",
                      gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0),
                      tickfontsize, guidefontsize, titlefontsize,
                      xlabel="POIe left",xlims,
                      ylabel="POIe right" ,ylims,
                      zlims, camera=(64, 10), size=(800,800))
        GEplots3d[iv] = p
        savefig(p, joinpath(OUTDIR, "$(iv)_GuessingEntropy_POIe.pdf"))
    end

    ps = [GEplots3d[iv] for iv in IVs]
    title = reshape([L"GE of $\mathit{%$(iv)}$" for iv in IVs], 1, length(IVs))
    plot(ps...;layout=(1,length(IVs)),size=(2400,800),margin=(10,:mm))
    savefig(joinpath(OUTDIR, "GuessingEntropy_POIe_3d.pdf"))
    if show gui();print("\rpress enter to close plot           ");readline() end
end

function plotGE_POIe_2d(GEtables; IVs, POIe_left_list, POIe_right_list, show=true)
    GEplots2d, POIe_lefts, POIe_rights = Dict(), POIe_left_list.÷ppc, POIe_right_list.÷ppc
    for iv in IVs
        xlims = (minimum(POIe_lefts),maximum(POIe_rights))
        ylims = (minimum(POIe_lefts),maximum(POIe_rights))
        u,l   = maximum(GEtables[iv]),minimum(GEtables[iv])
        diff  = u - l
        zlims  = (l-0.1*diff, u+0.1*diff) # or :auto
        
        p = plot(ylims=zlims; title="GE of $(iv)", xguide="POIe right")
        for (i,POIe_left) in enumerate(POIe_left_list)
            plot!(Roi_r.÷ppc, GEtables[iv][i,:]; markershape=:circle, mswidth=0, label="roi_l=$(roi_l÷ppc)")
        end
        GEplots2d[iv] = p
    end

    ps = [GEplots3d[iv] for iv in IVs]
    title = reshape(["GE of $(iv)" for iv in IVs], 1, 4)
    plot(ps...;layout=(1,4),size=(2400,800),margin=(10,:mm))
    savefig("GuessingEntropy_ROI_3d.pdf")
    if show gui();print("\rpress enter to close plot           ");readline() end

    plot(values(GEplots2d)...,size=(1200,900))
    savefig("GuessingEntropy_POIe_2d.pdf")
    if show gui();print("\rpress enter to close plot           ");readline() end
end


function main()

    isdir(OUTDIR) || mkdir(OUTDIR)
    TemplateDir, TargetDir = tplDir[tplidx], tgtDir[tgtidx]
    resultfile = getresultfile(;method, TemplateDir, TargetDir, postfix)
    println("plotting GE results from file: ",resultfile)
    GEtables = Dict(iv=>loadGE(resultfile; iv, POIe_left_list, POIe_right_list) for iv in IVs); GEtables[:β] = GEtables[:XY]; GEtables[:s] = GEtables[:S]
    plotGE_POIe_3d(GEtables; IVs=[:Buf, :β, :s], POIe_left_list, POIe_right_list, show=showfig)

end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

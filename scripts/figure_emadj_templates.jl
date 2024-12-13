using Statistics, StatsPlots
using TemplateAttack
using TemplateAttack:loaddata, trace_normalize, plotdatascatter!
using EMAlgorithm:emalg_addprocs
using LeakageAssessment:groupbyval
using Plots

### Parameters ##########
include("Parameters.jl")
###

TemplateDIR = joinpath(@__DIR__, "../data/Figure8_EMadj/")
TargetDIR   = joinpath(@__DIR__, "../data/Figure8_EMadj/")
OUTDIR      = "results/"

postfix = "_test_K"
iv, nicvth = :S, 0.001
POIe_left,POIe_right = 80,20
byte=1
TemplateDIR = joinpath(bigscratchTracesDIR, DirHPFnew[:DK2], "lanczos2_25/", "Templates_POIe$(POIe_left)-$(POIe_right)/")
TargetDIR   = joinpath(bigscratchTracesDIR, DirHPFnew2[:MS2], "lanczos2_25_test_K/")

axes=[3,4]

### end of Parameters ###

function genfig()
    #newworkers = emalg_addprocs(Sys.CPU_THREADS÷2)
    template = loadtemplate(joinpath(TemplateDIR,"Templates_$(iv)_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"); byte)
    traces = template.ProjMatrix' *reshape(loaddata(joinpath(TargetDIR, "traces$(postfix)_lanczos2_25_proc.npy")), (10920,48000))
    IV     = reshape(loaddata(joinpath(TargetDIR,"$(iv)$(postfix)_proc.npy")),(16,48000))[byte,:]
    isdir(OUTDIR) || mkpath(OUTDIR)
    
    print("Plotting traces and templates...        \r")
    p=plot(;size=(1200,900), legendfontsize=16, gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0))
    plotdatascatter!(traces; axes, groupdict=groupbyval(IV))
    plotTemplate!(template; axes, linewidth=2)
    savefig(p, joinpath(OUTDIR, "traces_and_templates.pdf"))

    print("EM Adjustment...        \r")
    adjust!(template, traces; num_epoch=10, Σscale=2)
    p=plot(;size=(1200,900), legendfontsize=16, gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0))
    plotdatascatter!(traces; axes, groupdict=groupbyval(IV))
    plotTemplate!(template; axes, linewidth=2)
    savefig(p, joinpath(OUTDIR, "traces_and_templates_EMadj.pdf"))
    #rmprocs(newworkers)
end



function main()
    genfig()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

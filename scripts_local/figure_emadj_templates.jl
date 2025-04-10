using LaTeXStrings, Plots
using LeakageAssessment:groupbyval
using TemplateAttack
using TemplateAttack:loaddata
#using EMAlgorithm:emalg_addprocs, rmprocs

### Parameters ##########
include("Parameters.jl")
dataurl = "https://www.cl.cam.ac.uk/~cyp24/Figure8_EMadj/"
###

tplidx, tgtidx = :DK2, :MS2
postfix = "_test_K"
iv, nicvth = :XY, 0.001 # {(:Buf,0.004), (:XY, 0.001), (:X, 0.001)}
iv, nicvth = :X , 0.001 # {(:Buf,0.004), (:XY, 0.001), (:X, 0.001)}
POIe_left,POIe_right = 40,80
byte=1

TemplateDIR = joinpath(@__DIR__, "../data/Traces-Os/", DirHPFOs[tplidx], "lanczos2_25/Templates_POIe$(POIe_left)-$(POIe_right)/")
TargetDIR   = joinpath(@__DIR__, "../data/Traces-Os/", DirHPFOs[tgtidx], "lanczos2_25$(postfix)/")
OUTDIR      = "results/"
fileformat  = :png  # :png or :pdf

num_epoch, Σscale = 30, 4   # {:Buf=>(20, 16) , else=>(30, 4)}

axes=[1,2]
legendfontsize = 24
aspect_ratio   = :equal # :auto
grid           = true #false  # true

### end of Parameters ###


function plotEMdata(template, traces, IV; anno=nothing, kwargs...)
    traces = ndims(template)==size(traces,1) ? traces : template.ProjMatrix' *traces
    p=plot(;size=(1200,900), gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0), legendfontsize, aspect_ratio, grid, ticks=:none, kwargs...)
    plotdatascatter!(traces; axes, groupdict=groupbyval(IV))
    plotTemplate!(template; axes, linewidth=2)
    isnothing(anno) || annotate!(anno...)
    return p
end


function genfig(template, traces, IV; fileformat=:pdf, anno=nothing, kwargs...)
    print("Plotting traces and templates...             \r")
    p = plotEMdata(template, traces, IV; anno, kwargs...)
    print("evaluating...                                \r")
    acc = success_rate(template, traces, IV)
    println("template accuracy: ", acc)
    figname = "traces_and_templates_$(iv)_$(tplidx)to$(tgtidx)_acc$(string(acc)[2:6]).$fileformat"
    savefig(p, joinpath(OUTDIR, figname))
    
    print("EM Adjustment...                             \r")
    adjust!(template, traces; num_epoch, Σscale)
    p = plotEMdata(template, traces, IV; kwargs...)
    print("evaluating...                                \r")
    acc = success_rate(template, traces, IV)
    println("template accuracy: ", acc)
    figname = "traces_and_templates_EMadj_$(iv)_$(tplidx)to$(tgtidx)_acc$(string(acc)[2:6]).$fileformat"
    savefig(p, joinpath(OUTDIR, figname))
end



function main()
    # check and download file
    isdir(TemplateDIR) || mkpath(TemplateDIR)
    isdir(TargetDIR)   || mkpath(TargetDIR)
    templatefile = joinpath(TemplateDIR, "Templates_$(iv)_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
    tracefile    = joinpath(  TargetDIR, "traces$(postfix)_lanczos2_25_proc.h5")
    IVfile       = joinpath(  TargetDIR, "$(iv)$(postfix)_proc.h5")

    # load data
    template = loadtemplate(templatefile; byte)
    traces = loaddata(tracefile)
    if ndims(traces) == 3
        a, b, c = size(traces)
        traces  = reshape(traces, a, b*c)
    end
    traces = template.ProjMatrix' *traces
    IV     = reshape(loaddata(IVfile),(iv==:Buf ? 8 : 16,size(traces,2)))[byte,:]
    isdir(OUTDIR) || mkpath(OUTDIR)
    
    if (iv,tplidx,tgtidx,postfix) == (:XY,:DK2,:MS2,"_test_K")
        anno = (0.465, 0.17, (latexstring("\$β\$ = 4\n\$β\$ = 8"),24))
        genfig(template, traces, IV; fileformat, size=(1200,800), dpi=300, xlim=(0.15,0.60), ylim=(-0.1,0.2), legendcolumn=2, legend=:topleft, anno)
    elseif (iv,tplidx,tgtidx,postfix) == (:X,:DK2,:MS2,"_test_K")
        genfig(template, traces, IV; fileformat, size=(1200,800), dpi=300, xlim=(0.05,0.11), ylim=(-0.102,-0.062))
    else
        genfig(template, traces, IV; fileformat)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

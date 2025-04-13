using ArgParse, LinearAlgebra
using LaTeXStrings, Plots
using LeakageAssessment:groupbyval
using TemplateAttack
using TemplateAttack:loaddata
#using EMAlgorithm:emalg_addprocs, rmprocs

### Parameters ##########
include("Parameters.jl")
###

(tplidx, tgtidx) = (:DK2, :MS2)
postfix = "_test_K"
(iv, nicvth) = (:XY, 0.001) # {(:Buf,0.004), (:XY, 0.001), (:X, 0.001)}
(POIe_left,POIe_right) = (40, 80)
byte=1

TemplateDIR = joinpath(TracesDIR, DirHPFOs[tplidx], "lanczos2_25/Templates_POIe$(POIe_left)-$(POIe_right)/")
TargetDIR   = joinpath(TracesDIR, DirHPFOs[tgtidx], "lanczos2_25$(postfix)/")
OUTDIR      = "results/"
fileformat  = :png  # :png or :pdf

num_epoch, Σscale = 30, 4   # {:Buf=>(20, 16) , else=>(30, 4)}

axes=[1,2]
legendfontsize = 24
aspect_ratio   = :equal # :auto
grid           = true #false  # true

### end of Parameters ###

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--variable"
            help    = "targeted variable: X, XY, or Buf"
        "--output", "-o"
            help    = "output file"
    end
    return parse_args(s)
end

function setIVandNICVTH(variable)
    if isnothing(variable)
        return (iv, nicvth) # return the global iv and nicvth
    else
        _iv   = Symbol(uppercase(variable))
        if _iv in [:X, :XY, :BETA, :BUF]
            if _iv == :X
                return (:X, 0.001)
            elseif _iv == :BUF
                return (:Buf, 0.004)
            else
                return (:XY, 0.001)
            end
        else
            error("Unrecognize intermediate value: ",_iv,"; options: {X, XY, Buf}")
        end
    end
end

function plotEMdata(template, traces, IV; anno=nothing, kwargs...)
    traces = ndims(template)==size(traces,1) ? traces :
             LinearAlgebra.mul!(Matrix{Float64}(undef, ndims(template), size(traces,2)), transpose(template.ProjMatrix), traces)
    #p=plot(;size=(1200,900), gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0), legendfontsize, aspect_ratio, grid, ticks=:none, kwargs...)
    p=plot(;size=(1200,900), gridalpha=1.0, foreground_color_grid=RGBA(0.9,0.9,0.9,1.0), legendfontsize, aspect_ratio, grid, kwargs...)
    plotdatascatter!(traces; axes, groupdict=groupbyval(IV))
    plotTemplate!(template; axes, linewidth=2)
    isnothing(anno) || annotate!(anno...)
    return p
end


function genfig(template, traces, IV; outfile=nothing, fileformat=:pdf, anno=nothing, kwargs...)

    figname1(acc) = joinpath(OUTDIR, "traces_and_$(iv)_templates_$(tplidx)to$(tgtidx)_acc$(string(acc)[2:6]).$fileformat")
    figname2(acc) = joinpath(OUTDIR, "traces_and_$(iv)_templates_EMadj_$(tplidx)to$(tgtidx)_acc$(string(acc)[2:6]).$fileformat")

    print("Plotting traces and templates...             \r")
    p = plotEMdata(template, traces, IV; anno, kwargs...)
    print("evaluating...                                \r")
    acc = success_rate(template, traces, IV)
    println("template accuracy: ", acc)
    figname = isnothing(outfile) ? figname1(acc) : outfile*".$fileformat"
    savefig(p, figname)

    print("EM Adjustment...                             \r")
    adjust!(template, traces; num_epoch, Σscale)
    p = plotEMdata(template, traces, IV; kwargs...)
    print("evaluating...                                \r")
    acc = success_rate(template, traces, IV)
    println("template accuracy: ", acc)
    figname = isnothing(outfile) ? figname2(acc) : outfile*"_EMadj.$fileformat"
    savefig(p, figname)
end



function main()

    # process command line configurations
    args    = parse_commandline()
    outfile = args["output"]
    if !isnothing(outfile)
        ftype = Symbol(Base.match(r"\.([a-z]+)\z",outfile)[1])
        global fileformat = ftype in [:png, :pdf] ? ftype : fileformat
        outfile = replace(outfile, r"\.[a-z]+\z"=>"")
    end
    global (iv, nicvth) = setIVandNICVTH(args["variable"])


    # load file
    templatefile = joinpath(TemplateDIR, "Templates_$(iv)_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
    tracefile    = joinpath(  TargetDIR, "traces$(postfix)_lanczos2_25_proc.h5")
    IVfile       = joinpath(  TargetDIR, "$(iv)$(postfix)_proc.h5")

    # load data
    template = loadtemplate(templatefile; byte)
    traces   = loaddata(tracefile)
    traces   = ndims(traces) == 3 ? reshape(traces, size(traces,1), :) : traces
    traces   = LinearAlgebra.mul!(Matrix{Float64}(undef, ndims(template), size(traces,2)), transpose(template.ProjMatrix), traces)
    IV       = reshape(loaddata(IVfile), :, size(traces,2))[byte,:]
    isdir(OUTDIR) || mkpath(OUTDIR)

    # generate figures
    if (iv,tplidx,tgtidx,postfix) == (:XY,:DK2,:MS2,"_test_K")
        anno = (0.465, 0.17, (latexstring("\$β\$ = 4\n\$β\$ = 8"),24))
        genfig(template, traces, IV; outfile, fileformat, size=(1200,800), dpi=300, xlim=(0.15,0.60), ylim=(-0.1,0.2), legendcolumn=2, legend=:topleft, anno)
    elseif (iv,tplidx,tgtidx,postfix) == (:X,:DK2,:MS2,"_test_K")
        genfig(template, traces, IV; outfile, fileformat, size=(1200,800), dpi=300, xlim=(0.05,0.11), ylim=(-0.102,-0.062))
    else
        genfig(template, traces, IV; outfile, fileformat)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

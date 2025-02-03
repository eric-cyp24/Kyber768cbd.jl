using Printf, Statistics
using HDF5, Plots, ColorSchemes #mapc, colorschemes


### Parameters ##########
include("Parameters.jl")
TracesDIR = joinpath(@__DIR__, "../data/Traces/")
###
# key: (TraceNormalize, EMAdjust)
adj_type = Dict((1,1) => "Traces_Normalized_Templates_Adj_EM",
                (0,1) => "Traces_Unmodified_Templates_Adj_EM",
                (0,0) => "Traces_Templates_Unmodified",
                (1,0) => "Traces_Normalized")

tplDir, tgtDir  = DirHPFOs, DirHPFOs
IVs             = [:Buf]        #[:Buf, :XY, :X, :Y, :S] 
method          = :marginalize 
POIe_left, POIe_right = 40, 80

OUTDIR          = "results/"
KeyGenfname     = "KeyGen_Multi-Board_Single-Trace_Attack_Success_Rate.tex"
Encapsfname     = "Encaps_Multi-Board_Single-Trace_Attack_Success_Rate.tex"
### end of Parameters ###

function resulth5name(;IVs::Vector{Symbol}, method=method, POIe_left=POIe_left, POIe_right=POIe_right, TemplateDir)
    return "$(method)_$(join(IVs))_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(TemplateDir,"/"=>"_")[1:end-1]).h5"
end

function getSR(h5file, adjtype)  
    adjtype = adjtype in keys(adj_type) ? adj_type[adjtype] : adjtype
    dataset_path = joinpath(adjtype, "success_rate_single_trace")
    return try
        h5open(h5file, "r") do h5 read(h5, dataset_path) end
    catch e
        NaN
    end
end

function loadresult(adjtype; postfix="_test_K", templatelist, targetlist, IVs=IVs)
    resultdict = Dict()
    for (i,tplidx) in enumerate(templatelist)
        TrainDIR = tplidx in keys(tplDir) ? tplDir[tplidx] : pooledDir(devicespools[tplidx])
        for (j,tgt) in enumerate(targetlist)
            TargetDIR   = joinpath(TracesDIR, tgtDir[tgt], "lanczos2_25$(postfix)")
            resultfname = resulth5name(;IVs, method, POIe_left, POIe_right, TemplateDir=TrainDIR)
            resultfile  = joinpath(TargetDIR,"Results/Templates_POIe$(POIe_left)-$(POIe_right)/", resultfname)
            resultdict[(tplidx,tgt)] = getSR(resultfile, adjtype)
        end
    end
    return resultdict
end

function resultdict2table(resultdict; templatelist, targetlist)
    table = Matrix{Float64}(undef, length(templatelist),length(targetlist))
    for (i,tpl) in enumerate(templatelist)
        for (j,tgt) in enumerate(targetlist)
            table[i,j] = resultdict[(tpl,tgt)]
        end
    end
    return table
end


cs1 = ColorScheme(append!([RGB{Float64}(1,1,1)],colorschemes[:Reds_7][2:6]))
function cellcolortxt(num::AbstractFloat; alpha=0.75, trange=(0.0,1.0), 
                      cscheme::ColorScheme=cs1, reverse=true)
                      #cscheme::ColorScheme=colorschemes[:Reds_5], reverse=true)
    num = isnan(num) ? 0.0 : (num-trange[1]) / trange[2]
    num = reverse ? 1-num : num
    rgb = mapc(v->(1-alpha)+alpha*v, cscheme[num])
    return @sprintf("\\cellcolor[rgb]{%.2f,%.2f,%.2f}",rgb.r, rgb.g, rgb.b)
end

function latextablewrapper(;part, caption="", label="")
    txtline = ""
    if part == :begin
        txtline  = "\\begin{table}[H]\n%\\centering\n"
        txtline *= "\\caption{$(caption)}$(isempty(label) ? "" : " \\label{$(label)}")\n"
        txtline *= "\\begin{adjustbox}{width=1\\textwidth}\n"
        txtline *= "\\begin{tabular}{V{4} c V{2} c|c|c|c|c|c|c|c||c|c|c|c|c|c|c|c V{4}}\n"
    elseif part == :end
        txtline  = "\\end{tabular}\n"
        txtline *= "\\end{adjustbox}\n"
        txtline *= "\\end{table}\n"
    end
    return txtline
end

multirowcelltxt(n,txt;enlarge=true)="\\multirow{$n}{*}{$(enlarge ? "\\large " : "")$txt} "
function latextableheader1(header::AbstractVector; mrow=3, diagbox=("Profiling","Target"), beginline="\\hlineB{4}\n", endline="\\hlineB{2}\n")
    txtline  = beginline
    firstcelltxt = isnothing(diagbox) ? "" :
    "\\diagbox[width=\\textwidth/9+2\\tabcolsep, height=3\\line, innerrightsep=3pt]{$(diagbox[1])}{$(diagbox[2])}" # hand craft
    celltxts = [multirowcelltxt(mrow, firstcelltxt; enlarge=false) ; [multirowcelltxt(mrow, txt) for txt in header]]
    txtline *= join(celltxts, "& ") * "\\\\\n"
    for i in 1:mrow-1 txtline *= ("& "^length(header)) * "\\\\\n" end
    return txtline * endline
end

# headers = [(8,"TemplateAttack"),(8,"Tempalte Attack+EM Alg")]
function latextableheader2(headers::AbstractVector; nrow=2, endline="\\hlineB{2}\n")
    lines = ""
    for j in 1:nrow
        lines *= " "
        for (i,(w,h)) in enumerate(headers)
            hcell = j==nrow ? "" : "\\multirow{$nrow}{*}{\\Large{$h}}"
            if i == length(headers)
                lines *= " &\\multicolumn{$w}{c V{4}}{$hcell} \\\\\n"
            else
                lines *= " &\\multicolumn{$w}{c||}{$hcell}"
            end
        end
    end
    return lines * endline
end

function latextablecontent(table::AbstractMatrix, firstcolumn::AbstractVector, aspercentage=true; 
                           endline="\\hlineB{2}\n")
    rows, trange = [], (aspercentage ? (0.0,1.0) : (findmax(table)[1],findmin(table)[1]))
    for (b,row) in zip(firstcolumn, eachrow(table))
        txtline  = "{$(String(b))} & "
        if aspercentage
            txtline *= join([cellcolortxt(n)*@sprintf("%5.1f \\%% ",n*100) for n in row], "& ")
        else
            txtline *= join([cellcolortxt(n;trange)*@sprintf("%6.3f ",n)   for n in row], "& ")
        end
        txtline *= " \\\\\n"
        push!(rows, txtline)
    end
    return join(rows, "\\hline\n") * endline
end


function result2textable(outfile::AbstractString, postfix=postfix; caption=caption, IVs=IVs)
    
    # load data
    print("loading results...        \r") # somehow print("... \r") cause Segmentation fault when exiting...???
    resulttables = Dict()
    for adjtype in [(0,0,0),(0,0,1),(1,0,0),(1,0,1),(0,1,0),(0,1,1)]
        (TraceNormalize, PooledDevices, EMAlg) = adjtype
        templatelist = Bool(PooledDevices) ? devpoolsidx : deviceslist
        targetlist   = deviceslist
        resultdict   = loadresult((TraceNormalize,EMAlg); postfix, templatelist, targetlist, IVs)
        resulttables[adjtype] = resultdict2table(resultdict; templatelist, targetlist)
    end

    # write data to .tex
    print("writing result...     \r")
    open(outfile,"w") do f
        write(f, latextablewrapper(;part=:begin, caption))
        write(f, latextableheader1([deviceslist;deviceslist]; mrow=3, diagbox=("Profiling","Target")))
        write(f, latextableheader2([(8,"Template Attack"),(8,"Template Attack + EM-Adjusted Templates")]))
        write(f, latextablecontent([resulttables[(0,0,0)] resulttables[(0,0,1)]], deviceslist))
        write(f, latextableheader2([(8,"Traces Normalized"),(8,"Traces Normalized + EM-Adjusted Templates")]))
        write(f, latextablecontent([resulttables[(1,0,0)] resulttables[(1,0,1)]], deviceslist))
        devlist = [replace(String(dev),"no"=>"w/o ") for dev in devpoolsidx]
        write(f, latextableheader2([(8,"Multi-Device Training"),(8,"Multi-Device Training + EM-Adjusted Templates")]))
        write(f, latextablecontent([resulttables[(0,1,0)] resulttables[(0,1,1)]], devlist; endline="\\hlineB{4}\n"))
        write(f, latextablewrapper(;part=:end))
    end
    return
end



function main()

    isdir("results/") || mkdir("results/")

    println("Multi-device single-trace attacks: templates from KeyGen -> to KeyGen targets")
    postfix  = "_test_K"
    outfile  = joinpath(OUTDIR, KeyGenfname)
    caption  = "Single-trace attack success rate by marginalize $(join(IVs," ,")) of {\\Kyber}768.\\texttt{KenGen} from \\texttt{KeyGen} templates."
    result2textable(outfile, postfix; caption, IVs)

    println("Multi-device single-trace attacks: templates from KeyGen -> to Encaps targets")
    postfix  = "_test_E"
    outfile  = joinpath(OUTDIR, Encapsfname)
    caption  = "Single-trace attack success rate by marginalize $(join(IVs," ,")) of {\\Kyber}768.\\texttt{Encaps} from \\texttt{KeyGen} templates."
    result2textable(outfile, postfix; caption, IVs)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

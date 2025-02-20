using Printf, Statistics
using HDF5, Plots, ColorSchemes #mapc, colorschemes
using TemplateAttack:loaddata


### Parameters ##########
include("Parameters.jl")
TracesDIR = bigscratchTracesDIR
###

tpldev, tgtdev = :DK1, :DK1
Dir, postfix   = DirHPFOs, "_test_K"
method         = :BP # :marginalize or :BP
POIe_left, POIe_right = 80, 20
tabletype      = :Sucess_Rate #:Success_Rate # :Guessing_Entropy
adjtype        = "Traces_Templates_Unmodified/"

OUTDIR         = "results/"
outfname       = "KeyGen_Template_Accuracy_$(tgtdev).tex"

caption        = "Accuracy of Kyber-768.\\texttt{$(postfix == "_test_K" ? "KeyGen" : "Encaps")} template attack and SASCA inference."
### end of Parameters ###


# checkout: https://juliagraphics.github.io/ColorSchemes.jl/stable/catalogue/
function cellcolortxt(num::AbstractFloat; alpha=0.75, trange=(0.0,1.0), 
                      cscheme::ColorScheme=colorschemes[:Blues], reverse=true)
    num = isnan(num) ? 0.0 : (num-trange[1]) / (trange[2]-trange[1])
    num = reverse ? 1-num : num
    rgb = mapc(v->(1-alpha)+alpha*v, cscheme[num])
    return @sprintf("\\cellcolor[rgb]{%.2f,%.2f,%.2f}",rgb.r, rgb.g, rgb.b)
end

multirowcelltxt(n,txt)="\\multirow{$n}{*}{$txt} "
# header = ["Buf","x1","x2","y1","y2","s1","s2","SASCA 1","SASCA 2"]
function latextableheader(header::AbstractVector; mrow=2, diagbox=("Graph","Variable"), beginline="\\hlineB{4}\n", endline="\\hlineB{2}\n")
    txtline  = beginline
    firstcelltxt = isnothing(diagbox) ? "" :
    "\\diagbox[width=\\textwidth/9+2\\tabcolsep, height=2\\line, innerrightsep=3pt]{$(diagbox[1])}{$(diagbox[2])}" # hand craft
    celltxts = [multirowcelltxt(mrow, firstcelltxt) ; [multirowcelltxt(mrow, txt) for txt in header]]
    txtline *= join(celltxts, "& ") * " \\\\\n"
    for i in 1:mrow-1 txtline *= ("& "^length(header)) * " \\\\\n" end
    return txtline * endline
end

function latextablecontent(table::AbstractMatrix, firstcolumn::AbstractVector, aspercentage=true; 
                           endline="\\hlineB{4}\n", trange=nothing)
    trange = isnothing(trange) ? (aspercentage ? (0.,1.) : (findmax(table)[1],findmin(table)[1])) : 
                                 trange
    rows = []
    for (b,row) in zip(firstcolumn, eachrow(table))
        txtline  = "{$(String(b))} & "
        if aspercentage
            celltxts = [[cellcolortxt(n;trange)*@sprintf("%5.2f \\%% ",n*100) for n in row[1:end-2]] ; 
                        [cellcolortxt(n;trange)*@sprintf("%6.3f \\%% ",n*100) for n in row[end-1:end]]]
            #txtline *= join([cellcolortxt(n;trange)*@sprintf("%5.2f \\%% ",n*100) for n in row], "& ")
            txtline *= join(celltxts, "& ")
        else
            txtline *= join([cellcolortxt(n;trange)*@sprintf("%6.3f ",n)   for n in row], "& ")
        end
        txtline *= " \\\\\n"
        push!(rows, txtline)
    end
    return join(rows, "\\hline\n") * endline
end

function latextablewrapper(;part, caption="", label="")
    txtline = ""
    if part == :begin
        txtline  = "\\begin{table}[H]\n\\centering\n"
        txtline *= "\\caption{$(caption)}$(isempty(label) ? "" : " \\label{$(label)}")\n"
        txtline *= "\\begin{adjustbox}{width=1\\textwidth}\n"
        txtline *= "\\begin{tabular}{V{4} c V{2} c|c|c|c|c|c|c||c|c V{4}}\n"
    elseif part == :end
        txtline  = "\\end{tabular}\n"
        txtline *= "\\end{adjustbox}\n"
        txtline *= "\\end{table}\n"
    end
    return txtline
end

function result2textable_wrapper(tpldev::Symbol, tgtdev::Symbol; OUTDIR=OUTDIR, outfname=outfname, adjtype=adjtype, tabletype=tabletype, postfix=postfix, 
                                                         method=method, POIe_left=POIe_left, POIe_right=POIe_right)
    #resultfname = "Result_with_Template_from_$(replace(Dir[tpldev],"/"=>"_")[1:end-1]).h5"
    resultfname = "$(method)_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(Dir[tpldev],"/"=>"_")[1:end-1]).h5"
    resultfile  = joinpath(TracesDIR, Dir[tgtdev], "lanczos2_25$(postfix)/Results/Templates_POIe$(POIe_left)-$(POIe_right)/", resultfname)

    isdir(OUTDIR) || mkdir(OUTDIR)
    outfile     = joinpath(OUTDIR, outfname*(split(outfname,".")[end]=="tex" ? "" : ".tex"))
    result2textable(resultfile, outfile; adjtype, tabletype, postfix)
end

function result2textable(resultfile, outfile; adjtype=adjtype, tabletype=tabletype, postfix=postfix)
    datasetpath = joinpath(adjtype, String(tabletype))
    # load data...
    print("loading result...      \r")
    table = h5open(resultfile, "r") do h5
        buf,x,y,s = [read(h5, joinpath(datasetpath, String(iv))) for iv in [:Buf, :X, :Y, :S]]
        s_guess   = reshape(read(h5, joinpath(adjtype,"S_BP_guess")), (16,48000))
        s_true    = reshape(loaddata(joinpath(dirname(resultfile), "../../", "S$(postfix)_proc.h5")), (16,48000))
        SASCA_s   = mean(s_guess.==s_true;dims=2)
        table     = [buf x[1:2:end] x[2:2:end] y[1:2:end] y[2:2:end] s[1:2:end] s[2:2:end] SASCA_s[1:2:end] SASCA_s[2:2:end]]
        [table; mean(table; dims=1)]
    end

    ## write data to tex
    print("writing result...     \r") # somehow this cause Segmentation fault when exiting...???
    header      = ["Buf","x1","x2","y1","y2","s1","s2","SASCA 1","SASCA 2"]
    firstcolumn = [["FG$i" for i in 1:8]; "Total"]
    open(outfile,"w") do f
        write(f, latextablewrapper(;part=:begin, caption))
        write(f, latextableheader(header; mrow=2, diagbox=("Graph","Variable")))
        write(f, latextablecontent(table, firstcolumn; trange=(0.5,1.0)))
        write(f, latextablewrapper(;part=:end))
    end
end



function main()
    println("Template and SASCA accuracy: templates from $(Dir[tpldev])..._POIe$(POIe_left)-$(POIe_right)/ -> to target $(Dir[tgtdev])...$(postfix)")
    result2textable_wrapper(tpldev, tgtdev; OUTDIR, outfname, adjtype, tabletype, postfix, method, POIe_left, POIe_right)

end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

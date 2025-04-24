using Dates:Time, Second
using ArgParse, HDF5
using Kyber768cbd:loaddata, key_guessing, guessing_entropy, success_rate, tracesnormalize, loadTemplates, writeTemplates, writeTemplates_ldaspace
using Kyber768cbd:emalg_addprocs, rmprocs, singletraceattacks, Templates_EMadj!


### Parameters ##########
include("Parameters.jl")
numproc   = Sys.CPU_THREADS÷2  # Number of multi-process for EM adjustment
skipexist = false
###

tgtlist, tpllist, pooltpllist = [:MS2], deviceslist, devpoolsidx #deviceslist, deviceslist, devpoolsidx
tplDir  = DirHPFOs  # DirHPFnew
tgtDir  = DirHPFOs  # DirHPFnew
postfix = "_test_K"     # _test_E or _test_K
POIe_left, POIe_right = 40, 80
nicvth   , bufnicvth  = 0.001, 0.004
num_epoch, buf_epoch  = 30, 20
method  = :marginalize
### end of Parameters ###

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--targetOP", "--OP"
            help = "select the targeted Kyber operation: {KeyGen|Encaps}"
    end
    return parse_args(s)
end

function Cross_Device_Attack(Templateidx::Symbol, Targetidx::Symbol, postfix::AbstractString; resulth5overwrite::Bool=false,
                             method=:marginalize, TracesNormalization::Bool=false, EMadjust::Bool=false, evalGESR::Bool=true,
                             num_epoch=num_epoch, buf_epoch=buf_epoch, nicvth=nicvth, bufnicvth=bufnicvth,
                             POIe_left=POIe_left, POIe_right=POIe_right)
    # load buf templates
    print("loading templates...            ")
    tBuf = begin
        TemplateDir = Templateidx in deviceslist ? tplDir[Templateidx] : pooledDir(devicespools[Templateidx])
        TemplateDIR = joinpath(TracesDIR, TemplateDir , "lanczos2_25/", "Templates_POIe$(POIe_left)-$(POIe_right)/")
        loadTemplates(TemplateDIR, :Buf; nicvth=bufnicvth, POIe_left, POIe_right)
    end
    tBuf_origin = EMadjust ? deepcopy(tBuf) : nothing
    println("Done!")

    # load traces (targets)
    print("loading traces...               ")
    Traces, S_true = begin
         TargetDIR = joinpath(TracesDIR, tgtDir[Targetidx], "lanczos2_25$(postfix)/")
         ( loaddata( joinpath(TargetDIR, "traces$(postfix)_lanczos2_25_proc.h5") ),
           loaddata( joinpath(TargetDIR, "S$(postfix)_proc.h5") )                 )
    end
    println("Done!")

    # Trace normaliztion
    if TracesNormalization
        print("normalizing target traces...    ")
        # use memmap when free RAM is low
        Traces = tracesnormalize(Traces, tBuf[1]; memmap=Sys.free_memory()<sizeof(Traces)*2, TMPFILE)
        println("Done!")
    end

    # EM Adjustment
    if EMadjust
        println("adjusting templates...          ")
        emadjsecs = @elapsed begin
            Templates_EMadj!(tBuf, :Buf, Traces; num_epoch=buf_epoch, newprocs=false)
        end
        println("\r                 \r\e[1A\e[32CDone!")
    end


    # create result.h5 file
    begin println("Templates from: ",TemplateDir," -> to Target: ",joinpath(tgtDir[Targetidx],"lanczos2_25$postfix/"))
    resultfile   = "$(method)_Buf_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(TemplateDir,"/"=>"_")[1:end-1]).h5"
	OUTDIR       = joinpath(TargetDIR, "Results/Templates_POIe$(POIe_left)-$(POIe_right)/")
	isdir(OUTDIR) || mkpath(OUTDIR)
    outfile      = joinpath(OUTDIR, resultfile) #joinpath(TargetDIR, resultfile)
    h5resultpath = TracesNormalization ? (EMadjust ? "Traces_Normalized_Templates_Adj_EM/" : "Traces_Normalized/") :
                                         (EMadjust ? "Traces_Unmodified_Templates_Adj_EM/" : "Traces_Templates_Unmodified/")
    println("writing result to file: ",outfile)
    ## "w":create & overwite, "cw": create or modify
    h5open(outfile, resulth5overwrite ? "w" : "cw") do h5
        haskey(h5, h5resultpath) && delete_object(h5, h5resultpath)
    end
    end

    # write Templates to result.h5
    print("writing templates...            ")
    group_path = "Templates/Buf/"
    if EMadjust
        try
            loadTemplates(outfile; group_path) == tBuf_origin || writeTemplates(outfile, tBuf_origin; group_path, compressed=true)
        catch KeyError
            writeTemplates(outfile, tBuf_origin; group_path, compressed=true)
        end
        writeTemplates_ldaspace(outfile, tBuf; group_path=joinpath(h5resultpath,"Templates_LDA/Buf/"), include_projMatrix=false)
    else
        resulth5overwrite && writeTemplates(outfile, tBuf; group_path, compressed=true)
        loadTemplates(outfile; group_path) == tBuf || error("templates in $group_path doesn't match tBuf")
    end

    println("Done!")

    # test Template -> write s_guess, Successrate, total/single-trace
    begin println("Single-Trace Attack...          ")
    attacksecs = @elapsed begin
        S_guess = singletraceattacks(Traces; tBuf, S_true, showprogress=true)
    end
    result  = (S_guess.==S_true)
    acc     = sum(result)/length(result)
    result_eachtrace = map(all,eachcol(result))
    sr_single_trace  = sum(result_eachtrace)/length(result_eachtrace)
    println("\r                 \r\e[1A\e[32CDone!") end

    # Guessing Entropy & Success Rate
    iv, tIV = :Buf, tBuf
    if evalGESR
        println("evaluating GE & SR...           ")
        traces = reshape(Traces,size(Traces,1),:)
        GEdict, SRdict = Dict(), Dict()
        evalsecs = @elapsed begin
            ivfile  = joinpath(TargetDIR, "$(String(iv))$(postfix)_proc.h5")
            IV_true = reshape(loaddata(ivfile), length(tIV), : )
            GEdict[iv] = Vector{Float32}(undef, size(IV_true,1))
            SRdict[iv] = Vector{Float32}(undef, size(IV_true,1))
            key_guesses = Array{Int16,3}(undef, (length(tIV[1]),size(traces,2),size(IV_true,1)))
            @sync Threads.@threads for byte in 1:size(IV_true,1)
                # "\e[" is "Control Sequence Initiator"
                print(iv," byte:\e[$(byte*3-(byte÷10+1))C$(byte)\r")
                key_guesses[:,:,byte]   = key_guessing(tIV[byte], traces)
                @views GEdict[iv][byte] = guessing_entropy( key_guesses[:,:,byte], IV_true[byte,:])
                @views SRdict[iv][byte] = success_rate(     key_guesses[:,:,byte], IV_true[byte,:])
            end
            print("                                                           \r")
        end
        println("\r                 \r\e[1A\e[32CDone!")
    end

    # write SASCA & Single-Trace Attack result
    print("writing single-trace attack result...   ")
    h5open(outfile, "cw") do h5
        g = haskey(h5,h5resultpath) ? h5[h5resultpath] : create_group(h5, h5resultpath)
        write(g, "S_guess", S_guess)
        write(g, "success_rate_total", acc) # accuracy
        write(g, "success_rate_single_trace", sr_single_trace)
        if evalGESR
            write(g, joinpath("Guessing_Entropy/",String(iv)), GEdict[iv])
            write(g, joinpath(    "Success_Rate/",String(iv)), SRdict[iv])
        end
    end
    println("Done!")

    println("Success Rate (accuracy): ",acc,", Single-Trace Success Rate: ",sr_single_trace)
    EMadjust && print("EM adjustment: ",Time(0)+Second(floor(emadjsecs)),"\t")
	print("Single-Trace Attack: ",Time(0)+Second(floor(attacksecs)),"\t")
	println("Evaluation: ",Time(0)+Second(floor(evalsecs)),"\n")
    return
end



function main()

    args = parse_commandline()
    isnothing(args["targetOP"]) || begin
        targetOP = lowercase(args["targetOP"])
        if targetOP == "keygen" || targetOP == "k"
            global postfix = "_test_K"
        elseif targetOP == "encaps" || targetOP == "e"
            global postfix = "_test_E"
        else
            global postfix = "_test_K"
        end
    end

    newworkers = emalg_addprocs(numproc)
    for tgtidx in tgtlist
        for tplidx in tpllist
        println("#### Template from ",tplidx," -> Target ",tgtidx,postfix," ####")

        if skipexist
            resultfile   = "$(method)_Buf_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(tplDir[tplidx],"/"=>"_")[1:end-1]).h5"
            TargetDIR    = joinpath(TracesDIR, tgtDir[tgtidx], "lanczos2_25$(postfix)/")
            OUTDIR       = joinpath(TargetDIR, "Results/Templates_POIe$(POIe_left)-$(POIe_right)/")
            isfile(joinpath(OUTDIR, resultfile)) && continue
        end

        # Unmodified Templates & Traces
        println("*** Unmodified Templates & Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=true,
                             TracesNormalization=false, EMadjust=false, num_epoch, buf_epoch)
        println("**********************************************")
        GC.gc()

        # Unmodified Templates & Normalized Traces
        println("*** Unmodified Templates & Normalized Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=true, EMadjust=false, num_epoch, buf_epoch)
        println("**********************************************")
        GC.gc()

        # Adjusted Templates & Unmodified Traces
        println("*** Adjusted Templates & Unmodified Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=false, EMadjust=true, num_epoch, buf_epoch)
        println("**********************************************")
        GC.gc()

        # Adjusted Templates & Normalized Traces
        println("*** Adjusted Templates & Normalized Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=true, EMadjust=true, num_epoch, buf_epoch)
        println("**********************************************")
        GC.gc()
        println("#########################################################################\n\n")
        end

        for tplidx in pooltpllist
        println("#### Template from ",tplidx," -> Target ",tgtidx,postfix," ####")

        if skipexist
            resultfile   = "$(method)_Buf_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(pooledDir(devicespools[tplidx]),"/"=>"_")[1:end-1]).h5"
            TargetDIR    = joinpath(TracesDIR, tgtDir[tgtidx], "lanczos2_25$(postfix)/")
            OUTDIR       = joinpath(TargetDIR, "Results/Templates_POIe$(POIe_left)-$(POIe_right)/")
            isfile(joinpath(OUTDIR, resultfile)) && continue
        end

        # Unmodified Templates & Traces
        println("*** Unmodified Templates & Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=true,
                             TracesNormalization=false, EMadjust=false, num_epoch, buf_epoch)
        println("**********************************************")

        # Adjusted Templates & Unmodified Traces
        println("*** Adjusted Templates & Unmodified Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=false, EMadjust=true, num_epoch, buf_epoch)
        println("**********************************************")
        println("#########################################################################\n\n")
        end
    end
    rmprocs(newworkers)
	return
end

if abspath(PROGRAM_FILE) == @__FILE__
    mkpath(TMPDIR)
    global TMPFILE, io = mktemp(TMPDIR); close(io)
    println("TMPFILE: ",TMPFILE)
    main()
    isempty(readdir(TMPDIR)) && rm(TMPDIR)
end

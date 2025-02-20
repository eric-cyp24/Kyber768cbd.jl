using Dates:Time, Second
using Mmap:mmap
using OffsetArrays
using HDF5
using TemplateAttack
using TemplateAttack:loaddata, trace_normalize, key_guessing
using EMAlgorithm:emalg_addprocs, rmprocs


### Parameters ##########
include("Parameters.jl")
TracesDIR = joinpath(@__DIR__, "../data/Traces-O3/")
#TMPFILE   = joinpath(@__DIR__, "../data/", "TemplateAttack.jl.tmp")
numproc   = Sys.CPU_THREADS÷2  # Number of multi-process for EM-adj
skipexist = true
###

tgtlist, tpllist, pooltpllist = deviceslist, [], devpoolsidx #deviceslist, deviceslist, devpoolsidx
tplDir  = DirHPFO3  # DirHPFnew
tgtDir  = DirHPFO3  # DirHPFnew
postfix = "_test_K"     # _test_E or _test_K
POIe_left, POIe_right = 40, 80
nicvth   , bufnicvth  = 0.001, 0.004
num_epoch, buf_epoch  = 30, 20
method  = :marginalize  #:marginalize or :BP
### end of Parameters ###

### single-trace attacks ###

bufx1(buf) = (buf >> 0) & 0x3
bufy1(buf) = (buf >> 2) & 0x3
bufx2(buf) = (buf >> 4) & 0x3
bufy2(buf) = (buf >> 6) & 0x3

HW = count_ones
bufs1(buf) = HW(bufx1(buf))-HW(bufy1(buf))
bufs2(buf) = HW(bufx2(buf))-HW(bufy2(buf))

function CBDmargin_Buf(Pbuf::AbstractVector; prob::Bool=false)
    # Enum prob
    s1_prob, s2_prob = OffsetArray(zeros(5),-2:2), OffsetArray(zeros(5),-2:2)
    for b in 0:255
        s1_prob[bufs1(b)] += Pbuf[b]
        s2_prob[bufs2(b)] += Pbuf[b]
    end
    return prob ? [s1_prob./sum(s1_prob), s2_prob./sum(s2_prob)] : [argmax(s1_prob),argmax(s2_prob)]
end

function CBD_TA_margin!(s_guess::AbstractVector, trace::AbstractVector, tBuf::Vector{Template}; prob::Bool=false)
    # Template Attack
    Buf_distributions = OffsetArray(reduce(hcat, [likelihoods(tbuf, trace) for tbuf in tBuf]), 0:255, 1:8 )

    # Marginalize Probability
    for i in 1:8
        s_guess[2*i-1:2*i] .= CBDmargin_Buf(view(Buf_distributions,:,i); prob)
    end
    return s_guess
end
function CBD_TA_margin(traces::AbstractMatrix, tBuf::Vector{Template}; prob::Bool=false)
    s_guess = Vector{Int16}(undef, 2*length(tBuf)*size(traces,2))
    @sync Threads.@threads for i in 1:size(traces,2)
        @views CBD_TA_margin!(s_guess[16*i-15:16*i], traces[:,i], tBuf; prob)
    end
    return s_guess
end

"""
    singletraceattacks(Traces::AbstractArray, tBuf::Vector{Template}; S_true::AbstractMatrix=[;;], showprogress::Bool=true)

"""
function singletraceattacks(Traces::AbstractArray, tBuf::Vector{Template}; S_true::AbstractMatrix=[;;], showprogress::Bool=true)
    S_guess = []
    if isempty(S_true)
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n,"  \r")
            push!(S_guess, CBD_TA_margin(trace, tBuf))
        end
    else
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n," -> ")
            push!(S_guess, CBD_TA_margin(trace, tBuf))
            showprogress && print(S_guess[end]==view(S_true,:,n) ? "O\r" : "X\r")
        end
    end
    return stack(S_guess)
end

function Cross_Device_Attack(Templateidx::Symbol, Targetidx::Symbol, postfix::AbstractString; resulth5overwrite::Bool=false, method=:marginalize,
                             TracesNormalization::Bool=false, EMadjust::Bool=false, num_epoch=30, buf_epoch=5, evalGESR::Bool=true,
                             nicvth=nicvth, bufnicvth=bufnicvth, POIe_left=POIe_left, POIe_right=POIe_right)
    # load buf templates
    print("loading templates...            ")
    tBuf = begin
        TemplateDir = Templateidx in deviceslist ? tplDir[Templateidx] : pooledDir(devicespools[Templateidx])
        TemplateDIR = joinpath(TracesDIR, TemplateDir , "lanczos2_25/", "Templates_POIe$(POIe_left)-$(POIe_right)/")
        tbuffile    = joinpath(TemplateDIR, "Templates_Buf_proc_nicv$(string(bufnicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
        [loadtemplate(tbuffile; byte) for byte in 1:8 ]
    end
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
        Traces = tracesnormalize(Traces, tBuf[1]; TMPFILE)
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
        try delete_object(h5, h5resultpath) catch e end
    end end

    # write Templates to result.h5
    print("writing templates...            ")
    writeTemplates(outfile, joinpath(h5resultpath, "Templates/"); tBuf)
    println("Done!")

    # test Template -> write s_guess, Successrate, total/single-trace
    begin println("Single-Trace Attack...          ")
    attacksecs = @elapsed begin
        S_guess = singletraceattacks(Traces, tBuf; S_true, showprogress=true)
    end
    result  = (S_guess.==S_true)
    sr      = sum(result)/length(result)
    result_eachtrace = map(all,eachcol(result))
    sr_single_trace  = sum(result_eachtrace)/length(result_eachtrace)
    println("\r                 \r\e[1A\e[32CDone!") end

    # Guessing Entropy & Success Rate
    iv, tIV = :Buf, tBuf
    if evalGESR
        println("evaluating GE & SR...           ")
        a,b,c = size(Traces)
        Traces = reshape(Traces,(a,b*c))
        GEdict, SRdict = Dict(), Dict()
        evalsecs = @elapsed begin
            ivfile  = joinpath(TargetDIR, "$(String(iv))$(postfix)_proc.h5")
            IV_true = reshape(loaddata(ivfile), (length(tIV),b*c) )
            GEdict[iv] = Vector{Float32}(undef, size(IV_true,1))
            SRdict[iv] = Vector{Float32}(undef, size(IV_true,1))
            key_guesses = Array{Int16,3}(undef, (length(tIV[1]),size(Traces,2),size(IV_true,1)))
            @sync Threads.@threads for byte in 1:size(IV_true,1)
                # "\e[" is "Control Sequence Initiator"
                print(iv," byte:\e[$(byte*3-(byte÷10+1))C$(byte)\r")
                key_guesses[:,:,byte] = key_guessing(tIV[byte], Traces)
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
        g = try h5[h5resultpath] catch e create_group(h5, h5resultpath) end
        write(g, "S_guess", S_guess)
        write(g, "success_rate_total", sr)
        write(g, "success_rate_single_trace", sr_single_trace)
        if evalGESR
            write(g, joinpath("Guessing_Entropy/",String(iv)), GEdict[iv])
            write(g, joinpath(    "Success_Rate/",String(iv)), SRdict[iv])
        end
    end
    println("Done!")

    println("Success Rate: ",sr,", Single-Trace Success Rate: ",sr_single_trace)
    EMadjust && print("EM adjustment: ",Time(0)+Second(floor(emadjsecs)),"\t")
	print("Single-Trace Attack: ",Time(0)+Second(floor(attacksecs)),"\t")
	println("Evaluation: ",Time(0)+Second(floor(evalsecs)),"\n")
    return 
end

#############################

### template portability techniques ###

function writeTemplates(filename::AbstractString, templatepath::AbstractString; tBuf=nothing, tX=nothing, tY=nothing, tS=nothing, tXY=nothing)
    for (iv,templates) in zip([:Buf,:X,:Y,:S, :XY],[tBuf, tX, tY, tS, tXY])
        isnothing(templates) && continue
        group_path = joinpath(templatepath,String(iv))
        for (byte,t) in enumerate(templates)
            writetemplate(filename, t; group_path, byte)
        end
    end
end

function tracesnormalize(Traces::AbstractArray, template::Template; TMPFILE=nothing)
    a,b,c  = size(Traces)
    if isnothing(TMPFILE)
        return reshape( trace_normalize(reshape(Traces,(a,b*c)),template), (a,b,c))
    else
        return open(TMPFILE,"w+") do f
           Traces_mmap    = mmap(f, typeof(Traces), size(Traces))
           Traces_mmap[:] = reshape( trace_normalize(reshape(Traces,(a,b*c)),template), (a,b,c) )
           Traces_mmap
        end
    end
end


function Templates_EMadj!(tIV::Vector{Template}, iv::Symbol, Traces::AbstractArray; num_epoch=20, newprocs::Bool=true)
    if ndims(Traces) == 3
        a,b,c = size(Traces)
        Traces = reshape(Traces, (a,b*c))
    end
    newworkers = newprocs ? emalg_addprocs(Sys.CPU_THREADS÷2) : []
    Templates_EMadj!(tIV, iv, Traces; num_epoch)
    newprocs && rmprocs(newworkers)
    return tIV
end
function Templates_EMadj!(tIV::Vector{Template}, iv::Symbol, Traces::AbstractMatrix; num_epoch=20)
    println("EM adjust -> $iv    ")
    EMerror = false
    for (byte,t) in enumerate(tIV)
        print("                                             -> byte: ",byte,"\r")
        dims, Σscale = ndims(t), 4
        while dims > 1
            try
                adjust!(t, Traces; num_epoch, dims, Σscale)
                break
            catch e
                EMerror = true
                if Σscale < 16
                    Σscale *= 2
                    println(iv," byte: ",byte," EM Algorithm error -> Σscale=", Σscale, "   ")
                else
                    dims -= 2
                    println(iv," byte: ",byte," EM Algorithm error -> dims=", dims, "   ")
                end
            end
        end
    end
    print("\r                                                             \r")
    EMerror || println("\e[1A\r                      \r") # erase EM adjust line
    return tIV
end

function CBDTemplates_EMadj!(CBDTemplates, Traces::AbstractArray; newprocs::Bool=true,
                             buf_epoch=5, buf_dims=16, num_epoch=30)
    if ndims(Traces) == 3
        a,b,c = size(Traces)
        Traces = reshape(Traces, (a,b*c))
    end
    newworkers = newprocs ? emalg_addprocs(Sys.CPU_THREADS÷2) : []
    for (iv, tIV) in zip([:Buf, :X, :Y, :S], CBDTemplates)
        Templates_EMadj!(tIV, iv, Traces; num_epoch=(iv==:Buf ? buf_epoch : num_epoch))
    end
    print("\r                    \r")
    newprocs && rmprocs(newworkers)
    return CBDTemplates
end

#######################################



function main()

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
    for i in 0:20
        if !isfile(TMPFILE*".$i")
            global TMPFILE *= ".$i"
            touch(TMPFILE)
            break
        end
    end
    println("TMPFILE: ",TMPFILE)
    main()
    rm(TMPFILE)
end

using HDF5, TemplateAttack, Distributed
using Dates:Time, Second
using TemplateAttack:loaddata, trace_normalize, key_guessing
using Mmap:mmap
import EMAlgorithm


### Parameters ##########
include("Parameters.jl")
include("../scripts/KyberCBDBP.jl")
TracesDIR = joinpath(@__DIR__, "../data/Traces/")
TMPFILE   = joinpath(@__DIR__, "../data/", "TemplateAttack.jl.tmp2")
###

tplDir  = DirHPFnew
tgtDir  = DirHPFnew
postfix = "_test_K"     # _test_E or _test_K
POIe_left, POIe_right = 80, 20
nicvth   , bufnicvth  = 0.001, 0.004
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

function CBDmargin(Pbuf::T, Px1::T, Py1::T, Ps1::T, Px2::T, Py2::T, Ps2::T; prob::Bool=false) where T<:AbstractVector
    # Enum prob
    s1_prob, s2_prob = OffsetArray(zeros(5),-2:2), OffsetArray(zeros(5),-2:2)
    for b in 0:255
        buf_prob = Pbuf[b] *Px1[bufx1(b)] *Py1[bufy1(b)] *Ps1[bufs1(b)] *Px2[bufx2(b)] *Py2[bufy2(b)] *Ps2[bufs2(b)]
        s1_prob[bufs1(b)] += buf_prob
        s2_prob[bufs2(b)] += buf_prob
    end
    return prob ? [s1_prob./sum(s1_prob), s2_prob./sum(s2_prob)] : [argmax(s1_prob),argmax(s2_prob)]
end

function CBD_TA_margin!(s_guess::AbstractVector, trace::AbstractVector, tBuf::T, tX::T, tY::T, tS::T; prob::Bool=false) where {T}
    # Template Attack
    Buf_distributions = OffsetArray(reduce(hcat, [likelihoods(tbuf, trace) for tbuf in tBuf]), 0:255, 1:8 )
    X_distributions   = OffsetArray(reduce(hcat, [likelihoods(  tx, trace) for tx   in tX  ]), 0:3  , 1:16)
    Y_distributions   = OffsetArray(reduce(hcat, [likelihoods(  ty, trace) for ty   in tY  ]), 0:3  , 1:16)
    S_distributions   = OffsetArray(reduce(hcat, [likelihoods(  ts, trace) for ts   in tS  ]),-2:2  , 1:16)
    Pbuf = view(Buf_distributions,:,:)
    Px1, Px2 = view(X_distributions,:,1:2:16), view(X_distributions,:,2:2:16)
    Py1, Py2 = view(Y_distributions,:,1:2:16), view(Y_distributions,:,2:2:16)
    Ps1, Ps2 = view(S_distributions,:,1:2:16), view(S_distributions,:,2:2:16)

    # Belief Propagation
    @views for i in 1:8
        s_guess[2*i-1:2*i] .= CBDmargin(Pbuf[:,i],Px1[:,i],Py1[:,i],Ps1[:,i],Px2[:,i],Py2[:,i],Ps2[:,i]; prob)
    end
    return s_guess
end
function CBD_TA_margin(traces::AbstractMatrix, tBuf::T, tX::T, tY::T, tS::T; prob::Bool=false) where {T}
    s_guess = Vector{Int16}(undef, size(tS,1)*size(traces,2))
    @sync Threads.@threads for i in 1:size(traces,2)
        @views CBD_TA_margin!(s_guess[16*i-15:16*i], traces[:,i], tBuf, tX, tY, tS; prob)
    end
    return s_guess
end

function CBD_TA_BP(trace::AbstractVector, tBuf::T, tX::T, tY::T, tS::T; iter=10, showprogress=false) where {T}
    # Template Attack
    Buf_distributions = [OffsetArray(likelihoods(tbuf, trace), 0:255) for tbuf in tBuf]
    X_distributions   = [OffsetArray(likelihoods(  tx, trace), 0:3  ) for tx in tX]
    Y_distributions   = [OffsetArray(likelihoods(  ty, trace), 0:3  ) for ty in tY]
    S_distributions   = [OffsetArray(likelihoods(  ts, trace),-2:2  ) for ts in tS]

    # Belief Propagation
    s_guess = Vector{Int16}(undef, 16)
    for i in 1:8
        ta_factors = Dict(:Tbuf => Factor([:buf], Buf_distributions[i]), 
                          :Tx1  => Factor([:x1] , X_distributions[2*i-1]),
                          :Tx2  => Factor([:x2] , X_distributions[2*i]),
                          :Ty1  => Factor([:y1] , Y_distributions[2*i-1]),
                          :Ty2  => Factor([:y2] , Y_distributions[2*i]),
                          :Ts1  => Factor([:s1] , S_distributions[2*i-1]),
                          :Ts2  => Factor([:s2] , S_distributions[2*i])   )
        s_guess[2*i-1:2*i] .= kyber_CBD_BP(ta_factors; iter, showprogress)
    end
    return s_guess
end
function CBD_TA_BP(traces::AbstractMatrix, tBuf::T, tX::T, tY::T, tS::T; iter=10, showprogress=false) where {T}
    s_guess = Vector{Int16}(undef, 16*48)
    @sync Threads.@threads for i in 1:size(traces,2)
        s_guess[16*i-15:16*i] .= CBD_TA_BP(view(traces,:,i), tBuf, tX, tY, tS; iter, showprogress)
    end
    return s_guess
end

CBD_STA = method in [:BP, :bp, :beliefpropagation] ? CBD_TA_BP : CBD_TA_margin
"""
    singletraceattacks(Traces::AbstractArray, tBuf::T, tX::T, tY::T, tS::T; S_true::AbstractMatrix=[;;], method=:marginalize) where {T}

`method` :marginalize or (:beliefpropagation or :BP)
"""
function singletraceattacks(Traces::AbstractArray, tBuf::T, tX::T, tY::T, tS::T; 
                           S_true::AbstractMatrix=[;;], showprogress::Bool=true) where {T}
    S_guess = []
    if isempty(S_true)
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n,"  \r")
            push!(S_guess, CBD_STA(trace, tBuf, tX, tY, tS))
        end
    else
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n," -> ")
            push!(S_guess, CBD_STA(trace, tBuf, tX, tY, tS))
            showprogress && print(S_guess[end]==view(S_true,:,n) ? "O\r" : "X\r")
        end
    end
    return stack(S_guess)
end

function Cross_Device_Attack(Templateidx::Symbol, Targetidx::Symbol, postfix::AbstractString; resulth5overwrite::Bool=false, method=:marginalize,
                             TracesNormalization::Bool=false, EMadjust::Bool=false, num_epoch=30, buf_epoch=5, evalGESR::Bool=true,
                             nicvth=nicvth, bufnicvth=bufnicvth, POIe_left=POIe_left, POIe_right=POIe_right)
    # load templates
    print("loading templates...            ")
    tBuf, tX, tY, tS = begin
         TemplateDir = Templateidx in deviceslist ? tplDir[Templateidx] : pooledDir(devicespools[Templateidx])
         TemplateDIR = joinpath(TracesDIR, TemplateDir , "lanczos2_25/", "Templates_POIe$(POIe_left)-$(POIe_right)/")
         loadCBDTemplates(TemplateDIR; nicvth, bufnicvth)
    end
    println("Done!")

    # load traces (targets)
    print("loading traces...               ")
    Traces, S_true = begin
         TargetDIR = joinpath(TracesDIR, tgtDir[Targetidx], "lanczos2_25$(postfix)/")
         ( loaddata( joinpath(TargetDIR, "traces$(postfix)_lanczos2_25_proc.npy") ),
           loaddata( joinpath(TargetDIR, "S$(postfix)_proc.npy") )                 )
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
            CBDTemplates_EMadj!((tBuf, tX, tY, tS), Traces; buf_epoch, num_epoch, newprocs=false)
        end
        println("\r                 \r\e[1A\e[32CDone!")
    end


    # create result.h5 file
    begin println("Templates from: ",TemplateDir," -> to Target: ",joinpath(tgtDir[Targetidx],"lanczos2_25$postfix/"))
    resultfile   = "$(method)_Result_with_Templates_POIe$(POIe_left)-$(POIe_right)_from_$(replace(TemplateDir,"/"=>"_")[1:end-1]).h5"
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
    writeTemplates(outfile, joinpath(h5resultpath, "Templates/"), tBuf, tX, tY, tS)
    println("Done!")

    # test Template -> write s_guess, Successrate, total/single-trace
    begin println("Single-Trace Attack...          ")
    attacksecs = @elapsed begin
        S_guess = singletraceattacks(Traces, tBuf, tX, tY, tS; S_true, showprogress=true)
    end
    result  = (S_guess.==S_true)
    sr      = sum(result)/length(result)
    result_eachtrace = map(all,eachcol(result))
    sr_single_trace  = sum(result_eachtrace)/length(result_eachtrace)
    println("\r                 \r\e[1A\e[32CDone!") end

    # Guessing Entropy & Success Rate
    if evalGESR
        println("evaluating GE & SR...           ")
        a,b,c = size(Traces)
        Traces = reshape(Traces,(a,b*c))
        GEdict, SRdict = Dict(), Dict()
        evalsecs = @elapsed begin
            @views for (iv, tIV) in zip([:Buf, :X, :Y, :S], [tBuf, tX, tY, tS])
                ivfile  = joinpath(TargetDIR, "$(String(iv))$(postfix)_proc.npy")
                IV_true = reshape(loaddata(ivfile), (length(tIV),b*c) )
                GEdict[iv] = Vector{Float32}(undef, size(IV_true,1))
                SRdict[iv] = Vector{Float32}(undef, size(IV_true,1))
                key_guesses = Array{Int16,3}(undef, (length(tIV[1]),size(Traces,2),size(IV_true,1)))
                @sync Threads.@threads for byte in 1:size(IV_true,1)
                    # "\e[" is "Control Sequence Initiator"
                    print(iv," byte:\e[$(byte*3-(byte÷10+1))C$(byte)\r")
                    key_guesses[:,:,byte] = key_guessing(tIV[byte], Traces)
                    GEdict[iv][byte] = guessing_entropy( key_guesses[:,:,byte], IV_true[byte,:])
                    SRdict[iv][byte] = success_rate(     key_guesses[:,:,byte], IV_true[byte,:])
                end
                print("                                                       \r")
            end
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
            for iv in (:Buf, :X, :Y, :S)
                write(g, joinpath("Guessing_Entropy/",String(iv)), GEdict[iv])
                write(g, joinpath(    "Success_Rate/",String(iv)), SRdict[iv])
            end
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

function loadCBDTemplates(filepath::AbstractString; nicvth=nicvth, bufnicvth=bufnicvth, templatepath::AbstractString="")
    if isdir(filepath)
        tbuffile = joinpath(filepath, "Templates_Buf_proc_nicv$(string(bufnicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
        txfile   = joinpath(filepath, "Templates_X_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
        tyfile   = joinpath(filepath, "Templates_Y_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")
        tsfile   = joinpath(filepath, "Templates_S_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5")

        tBuf = [loadtemplate(tbuffile; byte) for byte in 1:8 ]
        tX   = [loadtemplate(  txfile; byte) for byte in 1:16]
        tY   = [loadtemplate(  tyfile; byte) for byte in 1:16]
        tS   = [loadtemplate(  tsfile; byte) for byte in 1:16]
    elseif ishdf5(filepath)
        group_path = joinpath(templatepath, "Buf")
        tBuf = [loadtemplate(filepath; group_path, byte) for byte in 1:8 ]
        group_path = joinpath(templatepath, "X")
        tX   = [loadtemplate(filepath; group_path, byte) for byte in 1:16]
        group_path = joinpath(templatepath, "Y")
        tY   = [loadtemplate(filepath; group_path, byte) for byte in 1:16]
        group_path = joinpath(templatepath, "S")
        tS   = [loadtemplate(filepath; group_path, byte) for byte in 1:16]
    end
    return tBuf, tX, tY, tS
end

function writeTemplates(filename::AbstractString, templatepath::AbstractString, tBuf, tX, tY, tS)
    for (iv,templates) in zip([:Buf,:X,:Y,:S],[tBuf, tX, tY, tS])
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

function CBDTemplates_EMadj!(CBDTemplates, Traces::AbstractArray; newprocs::Bool=true,
                             buf_epoch=5, buf_dims=16, num_epoch=30)
    if ndims(Traces) == 3
        a,b,c = size(Traces)
        Traces = reshape(Traces, (a,b*c))
    end
    newworkers = newprocs ? EMAlgorithm.emalg_addprocs(Sys.CPU_THREADS÷2) : []
    #println("EMstart -> nprocs(): $(EMAlgorithm.nprocs()), workers(): $(EMAlgorithm.workers())")
    for (iv, tIV) in zip([:Buf, :X, :Y, :S], CBDTemplates)
        println("EM adjust -> $iv    ")
        for (byte,t) in enumerate(tIV)
            print("                                             -> byte: ",byte,"\r")
            if iv == :Buf
                Σscale = 1
                while buf_dims > 1
                    try 
                        adjust!(t, Traces; num_epoch=buf_epoch, dims=buf_dims, Σscale)
                        break
                    catch e
                        if Σscale != 2
                            Σscale = 2
                            println(iv," byte:",byte," EM Algorithm error -> Σscale=2   ")
                        else
                            buf_dims -= 2
                            println("buf_dims: ",buf_dims,"    ")
                        end
                    end
                end
            else
                try
                    adjust!(t,Traces; num_epoch, Σscale=1)
                catch e
                    println(iv," byte: ",byte," EM Algorithm error -> Σscale=2  ")
                    adjust!(t,Traces; num_epoch, Σscale=2)
                end 
            end
        end
        print("\r                                                             \r\e[1A")
    end
    print("\r                    \r")
    newprocs && rmprocs(newworkers)
    return CBDTemplates
end

#######################################



function main()

    newworkers = EMAlgorithm.emalg_addprocs(8)
    for tgtidx in deviceslist
        for tplidx in deviceslist
        println("#### Template from ",tplidx," -> Target ",tgtidx,postfix," ####")

        # Unmodified Templates & Traces
        println("*** Unmodified Templates & Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=true,
                             TracesNormalization=false, EMadjust=false, num_epoch=30, buf_epoch=5)
        println("**********************************************")

        # Unmodified Templates & Normalized Traces
        println("*** Unmodified Templates & Normalized Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=true, EMadjust=false, num_epoch=30, buf_epoch=5)
        println("**********************************************")

        # Adjusted Templates & Unmodified Traces
        println("*** Adjusted Templates & Unmodified Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=false, EMadjust=true, num_epoch=30, buf_epoch=5)
        println("**********************************************")

        # Adjusted Templates & Normalized Traces
        println("*** Adjusted Templates & Normalized Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=true, EMadjust=true, num_epoch=30, buf_epoch=5)
        println("**********************************************")
        println("#########################################################################\n\n")
        end

        for tplidx in devpoolsidx
        println("#### Template from ",tplidx," -> Target ",tgtidx,postfix," ####")

        # Unmodified Templates & Traces
        println("*** Unmodified Templates & Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=true,
                             TracesNormalization=false, EMadjust=false, num_epoch=30, buf_epoch=5)
        println("**********************************************")

        # Adjusted Templates & Unmodified Traces
        println("*** Adjusted Templates & Unmodified Traces ***")
        Cross_Device_Attack(tplidx, tgtidx, postfix; method, resulth5overwrite=false,
                             TracesNormalization=false, EMadjust=true, num_epoch=30, buf_epoch=5)
        println("**********************************************")
        println("#########################################################################\n\n")
        end
    end
    rmprocs(newworkers)
	return
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

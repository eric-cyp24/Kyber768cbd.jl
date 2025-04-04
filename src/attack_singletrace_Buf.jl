using Mmap:mmap
using OffsetArrays
using HDF5
using EMAlgorithm:emalg_addprocs, rmprocs


### single-trace attacks ###
eVT = Vector{Template}(undef,0)
function singletraceattacks(Traces::AbstractArray; tBuf=nothing, tXY=nothing, tX=nothing, tY=nothing, tS=nothing,
                                                   S_true::AbstractMatrix=[;;], showprogress::Bool=true)
    tIV = (1 .⊻ isnothing.((tBuf,tXY,tX,tY,tS)))
    if tIV == (1,0,0,0,0)
        return singletraceattacks_Buf(Traces, tBuf; S_true, showprogress)
    end
end

#### Buf Template   ####

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

function CBD_TA_margin_Buf!(s_guess::AbstractVector, trace::AbstractVector, tBuf::Vector{Template}; prob::Bool=false)
    # Template Attack
    Buf_distributions = OffsetArray(reduce(hcat, [likelihoods(tbuf, trace) for tbuf in tBuf]), 0:255, 1:8 )

    # Marginalize Probability
    for i in 1:8
        s_guess[2*i-1:2*i] .= CBDmargin_Buf(view(Buf_distributions,:,i); prob)
    end
    return s_guess
end
function CBD_TA_margin_Buf(traces::AbstractMatrix, tBuf::Vector{Template}; prob::Bool=false)
    s_guess = Vector{Int16}(undef, 2*length(tBuf)*size(traces,2))
    @sync Threads.@threads for i in 1:size(traces,2)
        @views CBD_TA_margin_Buf!(s_guess[16*i-15:16*i], traces[:,i], tBuf; prob)
    end
    return s_guess
end

"""
    singletraceattacks(Traces::AbstractArray, tBuf::Vector{Template}; S_true::AbstractMatrix=[;;], showprogress::Bool=true)

"""
function singletraceattacks_Buf(Traces::AbstractArray, tBuf::Vector{Template}; S_true::AbstractMatrix=[;;], showprogress::Bool=true)
    S_guess = []
    if isempty(S_true)
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n,"  \r")
            push!(S_guess, CBD_TA_margin_Buf(trace, tBuf))
        end
    else
        for (n,trace) in enumerate(eachslice(Traces,dims=3))
            showprogress && print(" ",n," -> ")
            push!(S_guess, CBD_TA_margin_Buf(trace, tBuf))
            showprogress && print(S_guess[end]==view(S_true,:,n) ? "O\r" : "X\r")
        end
    end
    return stack(S_guess)
end

#############################

### template portability techniques ###

function loadTemplates(templateDir::AbstractString, iv::Symbol; nicvth, POIe_left, POIe_right)
    filename = "Templates_$(iv)_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
    filepath = joinpath(templateDir, filename)
    numbytes = h5open(filepath) do h5 length(h5["Templates"]) end
    return [loadtemplate(filepath; byte) for byte in 1:numbytes]
end
function loadTemplates(templateDir::AbstractString; IVs::AbstractVector, nicvth=0.001, bufnicvth=0.004, POIe_left=0, POIe_right=0, verbose=true)
    templateDir = normpath(templateDir)
    verbose && println("loading templates from: ",templateDir)
    verbose && print("loading tempates of: ")
    IVtemplates = []
    for iv in IVs
        verbose && print(iv,"  ")
        if iv == :Buf
            push!(IVtemplates, loadTemplates(templateDir, iv; nicvth=bufnicvth, POIe_left, POIe_right))
        else
            push!(IVtemplates, loadTemplates(templateDir, iv; nicvth, POIe_left, POIe_right))
        end
    end
    verbose && println()
    return length(IVs)==1 ? IVtemplates[1] : IVtemplates
end


function writeTemplates(filename::AbstractString, templatepath::AbstractString; tBuf=nothing, tX=nothing, tY=nothing, tS=nothing, tXY=nothing)
    for (iv,templates) in zip([:Buf,:X,:Y,:S, :XY],[tBuf, tX, tY, tS, tXY])
        isnothing(templates) && continue
        group_path = joinpath(templatepath,String(iv))
        for (byte,t) in enumerate(templates)
            writetemplate(filename, t; group_path, byte)
        end
    end
end

function tracesnormalize(Traces::AbstractArray, template::Template; memmap::Bool=false, TMPFILE=nothing)
    traces = reshape(Traces, size(Traces,1), :)
    if memmap
        fname, f = isnothing(TMPFILE) ? mktemp() : (TMPFILE, open(TMPFILE, "w+"))
        Traces_mmap    = mmap(f, typeof(traces), size(traces))
        Traces_mmap[:] = traces
        trace_normalize!(Traces_mmap,template)
        close(f)
        return open(fname) do f mmap(f, typeof(Traces), size(Traces)) end
    else
        return reshape( trace_normalize(traces,template), size(Traces))
    end
end


function Templates_EMadj!(tIV::Vector{Template}, iv::Symbol, Traces::AbstractArray; num_epoch=20, newprocs::Bool=true)
    newworkers = newprocs ? emalg_addprocs(Sys.CPU_THREADS÷2) : []
    traces     = reshape(Traces, size(Traces,1), :)
    Templates_EMadj!(tIV, iv, traces; num_epoch)
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
    EMerror || print("\e[1A\r                      \r") # erase EM adjust line
    return tIV
end

function CBDTemplates_EMadj!(CBDTemplates, Traces::AbstractArray; newprocs::Bool=true,
                             buf_epoch=20, buf_dims=16, num_epoch=30)
    newworkers = newprocs ? emalg_addprocs(Sys.CPU_THREADS÷2) : []
    traces     = reshape(Traces, size(Traces,1), :)
    for (iv, tIV) in zip([:Buf, :XY, :X, :Y, :S], CBDTemplates)
        Templates_EMadj!(tIV, iv, traces; num_epoch=(iv==:Buf ? buf_epoch : num_epoch))
    end
    print("\r                    \r")
    newprocs && rmprocs(newworkers)
    return CBDTemplates
end

#######################################

using Mmap:mmap
using OffsetArrays
using HDF5
using EMAlgorithm:emalg_addprocs, rmprocs


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
                             buf_epoch=20, buf_dims=16, num_epoch=30)
    if ndims(Traces) == 3
        a,b,c = size(Traces)
        Traces = reshape(Traces, (a,b*c))
    end
    newworkers = newprocs ? emalg_addprocs(Sys.CPU_THREADS÷2) : []
    for (iv, tIV) in zip([:Buf, :XY, :X, :Y, :S], CBDTemplates)
        Templates_EMadj!(tIV, iv, Traces; num_epoch=(iv==:Buf ? buf_epoch : num_epoch))
    end
    print("\r                    \r")
    newprocs && rmprocs(newworkers)
    return CBDTemplates
end

#######################################

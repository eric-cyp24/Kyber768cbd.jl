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

### template read/write ###

templatefields = collect(Symbol.(TemplateAttack.templatefields))
const sharedfields = (:TraceMean, :TraceVar)
# keep the original template field order, for templates construction
const uniquefields = deleteat!(copy(templatefields), findall(x->x∈sharedfields, templatefields))

function loadTemplates(filepath::AbstractString; group_path="Templates/")
    # check if the Vector{Template} is stored in compressed form
    compressed = h5open(filepath) do h5
        (sharedfields ⊆ Symbol.(keys(h5[group_path]))) # Base.issubset (⊆) type: \subseteq
    end

    if compressed
        return loadTemplates_compressed(filepath; group_path)
    else
        numbytes = h5open(filepath) do h5 length(h5[group_path]) end
        return [loadtemplate(filepath; group_path, byte) for byte in 1:numbytes]
    end
end
function loadTemplates(templateDir::AbstractString, iv::Symbol; nicvth, POIe_left, POIe_right)
    filename = "Templates_$(iv)_proc_nicv$(string(nicvth)[2:end])_POIe$(POIe_left)-$(POIe_right)_lanczos2.h5"
    filepath = joinpath(templateDir, filename)
    return loadTemplates(filepath)
end
function loadTemplates(templateDir::AbstractString, IVs::Vector{Symbol}; nicvth, bufnicvth, POIe_left, POIe_right, verbose=true)
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

function loadTemplates_compressed(filepath::AbstractString; group_path="Templates/")
    templates = Vector{Template}()
    h5open(filepath) do h5
        # read sharedfields
        tshared  = [read_dataset(h5, joinpath(group_path, String(n))) for n in sharedfields]
        numbytes = length(h5[group_path]) - 2
        for byte in 1:numbytes
            g = open_group(h5, joinpath(group_path, "byte $byte"))
            t = [read_dataset(g, String(n)) for n in uniquefields]
            push!(templates, Template(tshared..., t...))
        end
    end
    return templates
end


function writeTemplates(filepath::AbstractString, templates::Vector{Template}; group_path="Templates/", overwrite=false, compressed=false)
    if compressed
        writeTemplates_compressed(filepath, templates; group_path, overwrite)
    else
        (overwrite && isfile(filepath)) && rm(filepath)
        for (byte, t) in enumerate(templates)
            writetemplate(filepath, t; group_path, byte)
        end
    end
end
function writeTemplates(filepath::AbstractString, templatepath::AbstractString; tBuf=nothing, tX=nothing, tY=nothing, tS=nothing, tXY=nothing)
    for (iv,templates) in zip([:Buf,:X,:Y,:S, :XY],[tBuf, tX, tY, tS, tXY])
        isnothing(templates) && continue
        group_path = joinpath(templatepath,String(iv))
        writeTemplates(filepath, templates; group_path)
    end
end

function writeTemplates_compressed(filepath::AbstractString, templates::Vector{Template}; group_path="Templates/", overwrite=false)
    # write templates
    h5open(filepath, overwrite ? "w" : "cw") do h5
        writeTemplates_compressed(h5, templates; group_path, overwrite)
    end
end
function writeTemplates_compressed(h5::HDF5.File, templates::Vector{Template}; group_path="Templates/", overwrite=false)
    # check templates all from the same dataset
    equalTraceMean = all([templates[1].TraceMean==t.TraceMean for t in templates])
    equalTraceVar  = all([templates[1].TraceVar ==t.TraceVar  for t in templates])
    (equalTraceMean && equalTraceVar) || ErrorException("TraceMean or TraceVar have different values, cannot compress")

    haskey(h5, group_path) && delete_object(h5, group_path)
    g = create_group(h5, group_path)
    # write shared parts: TraceMean, TraceVar
    for n in sharedfields
        write_dataset(g, String(n), getproperty(templates[1],n))
    end
    # write individual parts
    for (byte, t) in enumerate(templates)
        writetemplate_ldaspace(h5, t; group_path, byte, include_projMatrix=true)
    end
end

function writeTemplates_ldaspace(filepath::AbstractString, templates::Vector{Template}; group_path="Templates/", include_projMatrix=false)
    h5open(filepath, "cw") do h5
        for (byte, t) in enumerate(templates)
            writetemplate_ldaspace(h5, t; group_path, byte, include_projMatrix)
        end
    end
end

function writetemplate_ldaspace(h5::HDF5.File, t::Template; group_path="Templates/", byte=0, include_projMatrix=false)
    template_path = joinpath(group_path, "byte $byte")
    haskey(h5, template_path) && delete_object(h5, template_path)
    g = create_group(h5, template_path)
    labels = sort!(collect(keys(t.mvgs)))
    mus    = stack([t.mvgs[l].μ for l in labels])
    sigmas = stack([t.mvgs[l].Σ for l in labels])
    priors = [t.priors[l] for l in labels]
    for n in fieldnames(Template)
        if n in sharedfields
            continue
        elseif n == :ProjMatrix
            include_projMatrix && write_dataset(g, String(n), getproperty(t,n))
        elseif n == :mvgs
            write_dataset(g, "labels", labels)
            write_dataset(g,    "mus",    mus)
            write_dataset(g, "sigmas", sigmas)
        elseif n == :priors
            write_dataset(g, String(n), priors)
        else
            write_dataset(g, String(n), getproperty(t,n))
        end
    end
end



### template portability techniques ###

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

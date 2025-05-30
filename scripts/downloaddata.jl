using ArgParse, Downloads, HDF5, Printf
using CRC32c:crc32c
using Mmap:mmap

### Parameters ##########
url            = "https://www.cl.cam.ac.uk/research/security/datasets/kyber/data/"
TracesDIR      = normpath( joinpath(@__DIR__, "../data/Traces/") )
checksumfile   = joinpath(@__DIR__, "Traces-Os-pub-checksum.h5")
checksumfile_p = joinpath(@__DIR__, "Traces-Os-pub-profiling-checksum.h5")
checksumfile_a = joinpath(@__DIR__, "Traces-Os-pub-attack-checksum.h5")
checksumfile_r = joinpath(@__DIR__, "Traces-Os-pub-Results-checksum.h5")
###

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--quiet", "-q"
            action = :store_true
            help   = "supress printing of the file structure"
        "--profiling", "-p"
            action = :store_true
            help   = "download data for profiling (DK2 device)"
        "--attack", "-a"
            action = :store_true
            help   = "download data for attack (MS2 devices & Template files)"
        "--results", "-r"
            action = :store_true
            help   = "download result files"
    end
    return parse_args(s)
end


### download data files ########################

"""
    downloaddata(h5file::T, urlbase::T, dirbase::T; quiet=false) where T <: AbstractString

Given the paths and checksums from `h5file`, download data files from `urlbase` to `dirbase`
"""
function downloaddata(h5file::T, urlbase::T, dirbase::T; quiet=false) where T <: AbstractString
    print("loading checksum file: ",h5file,"    \e[K\r")
    h5open(h5file) do h5
        println("downloading files from: ",urlbase,"\e[K")
        for path in keys(h5["/"])
            walkh5(path; h5, urlbase, dirbase, quiet)
        end
        println("\nfiles downloaded to: $dirbase\n")
    end
end

"""
    walkh5(path; depth=0, h5::HDF5.File, urlbase::T, dirbase::T, quiet=false) where T<:AbstractString

Triverse the h5 file, download from `utlbase` to `dirbase` if the file doesn't exist
"""
function walkh5(path; depth=0, h5::HDF5.File, urlbase::T, dirbase::T, quiet=false) where T<:AbstractString
    if h5[path] isa HDF5.Group
        mkpath(joinpath(dirbase,path))
        quiet || println("  "^depth, basename(path), "/")
        for _path in keys(h5[path])
            walkh5(joinpath(path,_path); depth=depth+1, h5, urlbase, dirbase, quiet)
        end
    elseif h5[path] isa HDF5.Dataset
        filename = basename(path)
        checksum = read(h5, path)
        check = downloadfile(path, checksum; urlbase, dirbase)
        if check == 0
            quiet || println("  "^depth, filename, "\t -> already there")
        else
            check == checksum || error("something wrong with file: $(joinpath(urlbase,path))")
            quiet || println("  "^depth, filename, "\t -> downloaded")
        end
    end
end

"""
    downloadfile(filepath::T, checksum::UInt32; urlbase::T, dirbase::T) where T <: AbstractString

Download from `joinpath(urlbase,filepath)` to `joinpath(dirbase,filepath)`, skip if file is already there
"""
function downloadfile(filepath::T, checksum::UInt32; urlbase::T, dirbase::T) where T <: AbstractString
    url = joinpath(urlbase,filepath)
    dir = joinpath(dirbase,dirname(filepath))
    outfile = joinpath(dirbase,filepath)
    filename = basename(outfile)
    isdir(dir) || return error("$dir doesn't exist")
    if isfile(outfile) && crc32c(mmap(outfile)) == checksum
        #print(filename, " -> exist")
        return UInt32(0)
    else
        narrowdisplay = displaysize(stdout)[2] < max(length(filename)+36, 81)
        infostr = "downloading "*(narrowdisplay ? "file" : filename)
        n = length(infostr)
        print(infostr,"\r")
        progress = (total::Integer, now::Integer) -> @printf("\e[%dC -> progress: %6.2f %%\r",n, now/total*100)
        Downloads.download(url, outfile; progress=progress)
        #print(infostr," -> done!!            ")
        print(" "^length(infostr),"\e[K\r")
        return crc32c(mmap(outfile))
    end
end



function main()

    args = parse_commandline()
    quiet = args["quiet"]

    # download data
    if args["profiling"]
        downloaddata(checksumfile_p, url, TracesDIR; quiet)
    elseif args["attack"]
        downloaddata(checksumfile_a, url, TracesDIR; quiet)
    elseif args["results"]
        downloaddata(checksumfile_r, url, TracesDIR; quiet)
    else
        downloaddata(checksumfile  , url, TracesDIR; quiet)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

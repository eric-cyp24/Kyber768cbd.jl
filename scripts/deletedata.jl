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
        "--force", "-f"
            action = :store_true
            help   = "delete file and ignore checksum"
        "--quiet", "-q"
            action = :store_true
            help   = "supress printing of the file structure"
        "--profiling", "-p"
            action = :store_true
            help   = "delete data for profiling (DK2 device)"
        "--attack", "-a"
            action = :store_true
            help   = "delete data for attack (MS2 devices & Template files)"
        "--results", "-r"
            action = :store_true
            help   = "delete result files"
    end
    return parse_args(s)
end


### delete data files ########################

"""
    deletedata(h5file::T, dirbase::T; force=false, quiet=false) where T <: AbstractString

Given the paths and checksums from `h5file`, delete data files in `dirbase` dir
"""
function deletedata(h5file::T, dirbase::T; force=false, quiet=false) where T <: AbstractString
    print("loading checksum file: ",h5file,"    \e[K")
    h5open(h5file) do h5
        println("\rdeleting files in: ",dirbase,"\e[K")
        for path in keys(h5["/"])
            walkh5(path; h5, dirbase, force, quiet)
        end
        println("\nall the files in: ",dirbase," are removed\n")
    end
end

"""
    walkh5(path; depth=0, h5::HDF5.File, dirbase::T, force=false, quiet=false) where T<:AbstractString

Triverse `dirbase` according to the `h5` file, delete the listed files if it exists.
This function also deletes empty dirs.
"""
function walkh5(path; depth=0, h5::HDF5.File, dirbase::T, force=false, quiet=false) where T<:AbstractString
    fullpath = joinpath(dirbase, path)
    if h5[path] isa HDF5.Group && isdir(fullpath)
        quiet || println("  "^depth, basename(path), "/")
        for _path in keys(h5[path])
            walkh5(joinpath(path,_path); depth=depth+1, h5, dirbase, force, quiet)
        end
        isempty(readdir(fullpath)) && rm(fullpath)
    elseif h5[path] isa HDF5.Dataset && isfile(fullpath)
        filename = basename(path)
        checksum = read(h5, path)
        if deletefile(fullpath; checksum, force)
            quiet || println("  "^depth, filename, "\t -> deleted")
        else
            print("  "^depth, filename, "\t -> "); printstyled("preserved\n"; color=:yellow)
            printstyled("  "^depth, "Warning: "; color=:yellow, bold=true)
            println("checksum doesn't match, file might have been modified!")
            println("  "^depth, "         use the -f option to remove this file")
        end
    end
end

"""
    deletefile(filepath::T; checksum::UInt32=0, force=false) where T <: AbstractString

Delete file if `checksum` matches. Set `force=true` to ignore `checksum`.
"""
function deletefile(filepath::T; checksum::UInt32=0, force=false) where T <: AbstractString
    filechecksum = crc32c(mmap(filepath))
    if filechecksum == checksum || force
        rm(filepath)
        return true
    else
        return false
    end
end

function deletedir(dirpath::AbstractString; recursive::Bool=false)
    isdir(dirpath) && rm(dirpath; recursive)
end




function main()

    args = parse_commandline()
    force = args["force"]
    quiet = args["quiet"]

    # delete data
    if args["profiling"]
        deletedata(checksumfile_p, TracesDIR; force, quiet)
    elseif args["attack"]
        deletedata(checksumfile_a, TracesDIR; force, quiet)
    elseif args["results"]
        deletedata(checksumfile_r, TracesDIR; force, quiet)
    else
        deletedata(checksumfile  , TracesDIR; force, quiet)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

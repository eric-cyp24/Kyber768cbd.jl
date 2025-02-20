using Downloads, HDF5, Printf
using CRC32c:crc32c
using Mmap:mmap

### Parameters ##########
url          = "https://www.cl.cam.ac.uk/~cyp24/Traces-Os-pub/"
TracesDIR    = normpath( joinpath(@__DIR__, "../data/Traces/") )
checksumfile = joinpath(@__DIR__, "Traces-Os-pub-checksum.h5")
###



### generate the checksum.h5 file ##############
function genchecksum(outfile::AbstractString, dirbase::AbstractString)
    outfile *= split(checksumfile,".")[end]=="h5" ? "" : ".h5"
    dirorigin = pwd()
    h5open(outfile, "w") do h5
        cd(dirbase)
        for path in readdir(pwd())
            walkdir(path; h5)
        end
        cd(dirorigin)
    end
end

function walkdir(path; depth=0, h5::HDF5.File)
    ispath(path) || return error("$path doesn't exist")
    if isdir(path)
        println("  "^depth, basename(path), "/")
        for _path in readdir(path)
            walkdir(joinpath(path,_path); depth=depth+1, h5)
        end
    else isfile(path)
        filename = basename(path)
        checksum = crc32c(mmap(path))
        println("  "^depth, filename, "\t -> 0x", string(checksum, base=16))
        write(h5,path,checksum)
    end
end



### download data files ########################

"""
    downloaddata(h5file::T, urlbase::T, dirbase::T) where T <: AbstractString

Given the paths and checksums from `h5file`, download data files from `urlbase` to `dirbase`
"""
function downloaddata(h5file::T, urlbase::T, dirbase::T) where T <: AbstractString
    print("loading checksum file: ",h5file,"   \r")
    h5open(h5file) do h5
        println("downloading files from: $urlbase")
        for path in keys(h5["/"])
            walkh5(path; h5, urlbase, dirbase)
        end
        println("\nfiles downloaded to: $dirbase\n")
    end
end

"""
    walkh5(path; depth=0, h5::HDF5.File, urlbase::T, dirbase::T) where T<:AbstractString

Triverse the h5 file, download from `utlbase` to `dirbase` if the file doesn't exist
"""
function walkh5(path; depth=0, h5::HDF5.File, urlbase::T, dirbase::T) where T<:AbstractString
    if h5[path] isa HDF5.Group
        mkpath(joinpath(dirbase,path))
        println("  "^depth, basename(path), "/")
        for _path in keys(h5[path])
            walkh5(joinpath(path,_path); depth=depth+1, h5, urlbase, dirbase)
        end
    else h5[path] isa HDF5.Dataset
        filename = basename(path)
        checksum = read(h5, path)
        check = downloadfile(path, checksum; urlbase, dirbase)
        if check == 0
            println("  "^depth, filename, "\t -> already there")
        else
            check == checksum || error("something wrong with file: $(joinpath(urlbase,path))")
            println("  "^depth, filename, "\t -> downloaded")
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
        infostr = "downloading "*filename; n = length(infostr)
        print(infostr,"\r")
        progress = (total::Integer, now::Integer) -> @printf("\e[%dC -> progress: %6.2f %%\r",n, now/total*100)
        Downloads.download(url, outfile; progress=progress)
        #print(infostr," -> done!!            ")
        print(" "^length(infostr),"                      \r")
        return crc32c(mmap(outfile))
    end
end



function main()
    # generate checksums
    outfile = "Traces-Os-pub-checksum.h5"
    dirbase = joinpath(homedir(),"public_html/Traces-Os-pub/")
    genchecksum(outfile, dirbase)
    ## download data
    #downloaddata(checksumfile, url, TracesDIR)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

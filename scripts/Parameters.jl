
###
DataDIR     = get(ENV, "DATA_DIR", normpath(@__DIR__, "../data/"))
TracesDIROs = joinpath(DataDIR, "Traces-Os/")
TracesDIRO1 = joinpath(DataDIR, "Traces-O1/")
TracesDIRO3 = joinpath(DataDIR, "Traces-O3/")
TracesDIR   = joinpath(DataDIR, "Traces/")
TMPDIR      = joinpath(DataDIR, "tmp/")
TMPFILE     = joinpath( TMPDIR, "Kyber768cbd.jl.tmp")
###
### Parameters ##########
deviceslist = [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2]
devpoolsidx = [:noRS2, :noRS1, :noMS2, :noMS1, :noFN2, :noFN1, :noDK2, :noDK1]

# TracesDIROs = ".../Kyber768/Traces-Os/"
DirHPFOs = Dict(:DK1 => "SOCKET_HPF/DK1/test_20241219/",
                :DK2 => "SOCKET_HPF/DK2/test_20241219/",
                :FN1 => "SOCKET_HPF/FN1/test_20241220/",
                :FN2 => "SOCKET_HPF/FN2/test_20241220/",
                :MS1 => "SOCKET_HPF/MS1/test_20241221/",
                :MS2 => "SOCKET_HPF/MS2/test_20241221/",
                :RS1 => "SOCKET_HPF/RS1/test_20241222/",
                :RS2 => "SOCKET_HPF/RS2/test_20241222/")

# TracesDIRO1 = ".../Kyber768/Traces-O1/"
DirHPFO1 = Dict(:DK1 => "SOCKET_HPF/DK1/test_20240724/",
                :DK2 => "SOCKET_HPF/DK2/test_20240725/",
                :FN1 => "SOCKET_HPF/FN1/test_20240725/",
                :FN2 => "SOCKET_HPF/FN2/test_20240726/",
                :MS1 => "SOCKET_HPF/MS1/test_20240726/",
                :MS2 => "SOCKET_HPF/MS2/test_20240727/",
                :RS1 => "SOCKET_HPF/RS1/test_20240723/",
                :RS2 => "SOCKET_HPF/RS2/test_20240724/")

# TracesDIRO3 = ".../Kyber768/Traces-O3/"
DirHPFO3 = Dict(:DK1 => "SOCKET_HPF/DK1/test_20250102/",
                :DK2 => "SOCKET_HPF/DK2/test_20250108/",
                :FN1 => "SOCKET_HPF/FN1/test_20250109/",
                :FN2 => "SOCKET_HPF/FN2/test_20250109/",
                :MS1 => "SOCKET_HPF/MS1/test_20250110/",
                :MS2 => "SOCKET_HPF/MS2/test_20250110/",
                :RS1 => "SOCKET_HPF/RS1/test_20250111/",
                :RS2 => "SOCKET_HPF/RS2/test_20250111/")

srcDir(dev) = joinpath(TracesDIR, DirHPFOs[dev],"lanczos2_25/")

# pooled traces
pooledDir(devices)=joinpath("SOCKET_HPF/Pooled/Pooled_HPF/", join(sort(String.(devices)),"_")*"/")

devicespools = Dict(:noRS2 => [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS1],
                    :noRS1 => [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS2],
                    :noMS2 => [:DK1, :DK2, :FN1, :FN2, :MS1, :RS1, :RS2],
                    :noMS1 => [:DK1, :DK2, :FN1, :FN2, :MS2, :RS1, :RS2],
                    :noFN2 => [:DK1, :DK2, :FN1, :MS1, :MS2, :RS1, :RS2],
                    :noFN1 => [:DK1, :DK2, :FN2, :MS1, :MS2, :RS1, :RS2],
                    :noDK2 => [:DK1, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2],
                    :noDK1 => [:DK2, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2]);


### end of Parameters ###


scratchTracesDIR    = "/local/scratch/cyp24/Lab/Kyber768/Traces/"
bigscratchTracesDIR = "/local/bigscratch/cyp24/Lab/Kyber768/Traces/"
ext1TracesDIR       = "/local/ext1/Kyber768/Traces/"
###
TracesDIR   = joinpath(@__DIR__, "../data/Traces/")
TracesDIROs = joinpath(@__DIR__, "../data/Traces-Os/")
TMPFILE     = ispath("/local/scratch/cyp24/") ? "/local/scratch/cyp24/TemplateAttack.jl.tmp" :
                                                joinpath(@__DIR__, "../data/TemplateAttack.jl.tmp")
###
### Parameters ##########
deviceslist = [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2]
DirDCBlock = Dict(:DK1 => "SOCKET/DK1/test_20240712/",
                  :DK2 => "SOCKET/DK2/test_20240716/",
                  :FN1 => "SOCKET/FN1/test_20240703/",
                  :FN2 => "SOCKET/FN2/test_20240704/",
                  :MS1 => "SOCKET/MS1/test_20240708/",
                  :MS2 => "SOCKET/MS2/test_20240711/",
                  :RS1 => "SOCKET/RS1/test_20240710/",
                  :RS2 => "SOCKET/RS2/test_20240711/")

DirHPFold = Dict(:DK1 => "SOCKET_HPF/DK1/test_20240416/",
                 :DK2 => "SOCKET_HPF/DK2/test_20240416/",
                 :FN1 => "SOCKET_HPF/FN1/test_20240415/",
                 :FN2 => "SOCKET_HPF/FN2/test_20240415/",
                 :MS1 => "SOCKET_HPF/MS1/test_20240423/",
                 :MS2 => "SOCKET_HPF/MS2/test_20240413/",
                 :RS1 => "SOCKET_HPF/RS1/test_20240411/",
                 :RS2 => "SOCKET_HPF/RS2/test_20240409/",
                 :CWA => "STM32F/Board_A_hpf/test_20240424/")

DirHPFO1  = Dict(:DK1 => "SOCKET_HPF/DK1/test_20240724/",
                 :DK2 => "SOCKET_HPF/DK2/test_20240725/",
                 :FN1 => "SOCKET_HPF/FN1/test_20240725/",
                 :FN2 => "SOCKET_HPF/FN2/test_20240726/",
                 :MS1 => "SOCKET_HPF/MS1/test_20240726/",
                 :MS2 => "SOCKET_HPF/MS2/test_20240727/",
                 :RS1 => "SOCKET_HPF/RS1/test_20240723/",
                 :RS2 => "SOCKET_HPF/RS2/test_20240724/",
                 :CWA => "STM32F/Board_A_hpf/test_20240822/",
                 :CWB => "STM32F/Board_B_hpf/test_20240823/")

DirHPFnew2 = Dict(:DK1 => "SOCKET_HPF/DK1/test_20240930/",
                  :DK2 => "SOCKET_HPF/DK2/test_20240930/",
                  :FN1 => "SOCKET_HPF/FN1/test_20241001/",
                  :FN2 => "SOCKET_HPF/FN2/test_20241001/",
                  :MS1 => "SOCKET_HPF/MS1/test_20241002/",
                  :MS2 => "SOCKET_HPF/MS2/test_20241002/",
                  :RS1 => "SOCKET_HPF/RS1/test_20241003/",
                  :RS2 => "SOCKET_HPF/RS2/test_20241003/")

# TracesDIRO3 = ".../Kyber768/Traces-O3/"
DirHPFO3   = Dict(:DK4 => "SOCKET_HPF/DK4/test_20241029/")


# TracesDIR = ".../Kyber768/Traces-Os/"
DirHPFOs   = Dict(:DK4 => "SOCKET_HPF/DK4/test_20241218/",
                  :DK1 => "SOCKET_HPF/DK1/test_20241219/",
                  :DK2 => "SOCKET_HPF/DK2/test_20241219/",
                  :FN1 => "SOCKET_HPF/FN1/test_20241220/",
                  :FN2 => "SOCKET_HPF/FN2/test_20241220/",
                  :MS1 => "SOCKET_HPF/MS1/test_20241221/",
                  :MS2 => "SOCKET_HPF/MS2/test_20241221/",
                  :RS1 => "SOCKET_HPF/RS1/test_20241222/",
                  :RS2 => "SOCKET_HPF/RS2/test_20241222/")




# pooled traces
pooledDir(devices)=joinpath("SOCKET_HPF/Pooled/Pooled_HPF/", join(sort(String.(devices)),"_")*"/")

devpoolsidx  = [:noRS2, :noRS1, :noMS2, :noMS1, :noFN2, :noFN1, :noDK2, :noDK1]
devicespools = Dict(:noRS2 => [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS1],
                    :noRS1 => [:DK1, :DK2, :FN1, :FN2, :MS1, :MS2, :RS2],
                    :noMS2 => [:DK1, :DK2, :FN1, :FN2, :MS1, :RS1, :RS2],
                    :noMS1 => [:DK1, :DK2, :FN1, :FN2, :MS2, :RS1, :RS2],
                    :noFN2 => [:DK1, :DK2, :FN1, :MS1, :MS2, :RS1, :RS2],
                    :noFN1 => [:DK1, :DK2, :FN2, :MS1, :MS2, :RS1, :RS2],
                    :noDK2 => [:DK1, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2],
                    :noDK1 => [:DK2, :FN1, :FN2, :MS1, :MS2, :RS1, :RS2]);



### end of Parameters ###

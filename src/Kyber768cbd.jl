module Kyber768cbd

using TemplateAttack
using TemplateAttack:loaddata, trace_normalize, key_guessing
using EMAlgorithm:emalg_addprocs, rmprocs

include("Parameters.jl")

include("profiling.jl")
export loaddata, Kyber768_profiling, pooledTraces

include("attack_singletrace_Buf.jl")
export emalg_add_procs, rmprocs, singletraceattacks, writeTemplates, tracesnormalize, Templates_EMadj!, key_guessing


end # module Kyber768cbd

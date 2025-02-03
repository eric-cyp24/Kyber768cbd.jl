

## Download this repository
Clone this repository and the submodules to your local machine:
```
$ git clone --recursive https://github.com/eric-cyp24/Kyber768cbd.jl.git
$ cd Kyber768cbd.jl
```


## Install Julia
Follow the [Julia installation](https://docs.julialang.org/en/v1/manual/installation/)
guide to install [Julia](https://docs.julialang.org/en/v1.11/manual/getting-started/).
For Mac and Linux, Julia can be installed by the following command:
```
$ curl -fsSL https://install.julialang.org | sh
```


## download data
Download Templates from all devices (DK1-RS2), profiling traces from DK2, 
and attack traces from MS2. The default output dir is set to: 
`Kyber768cbd.jl/data/Traces-pub/`.

```
$ julia --project scripts_pub/checkdata.jl
```
Run the following code to generate LaTeX table source code.
```
$ julia --project scripts_pub/h5result2latextable_multiboardsingletrace.jl
```
Paste the generated codes (`results/...Success_Rate.tex`) into a LaTeX editor,
and you sould see the tables:
![Success Rate Table](scripts_pub/LaTeX_tables.png)
You can complete the MS2 columns of the table by:
First, build the device DK2 templates with the following profiling step.
Then, run the single-trace attacks from all devices' templates, to the MS2 target.


## profiling
Build the LDA-based templates from device DK2's profiling traces:
`data/Traces-pub/SOCKET_HPF/DK2/test_20241219/lanczos2_25/traces_lanczos2_25_proc.npy`.
The templates will be stored in the folder:
`data/Traces-pub/SOCKET_HPF/DK2/test_20241219/lanczos2_25/Templates_POIe40-80/`.

```
$ julia --project scripts_pub/profiling_kyber768cbd.jl
```

## attack
Run the single-trace attacks from all devices' templates to the M2 target device.
```
$ julia --project -t4 scripts_pub/attack_kyber768cbd_Buf_singletrace.jl
```
The attack results will be stored in the folder:
`data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25_test_K/Results/Templates_POIe40-80/`.
You can view the more detailed recorded data for the attacks with a HDF5 viwer,
for example: [myHDF5 online viewer](https://myhdf5.hdfgroup.org/)

For the Kyber768.Encaps traces, modify the script's Parameters section:
change the `postfix` from `"_test_K"` to `postfix = "_test_E"` at line 17
in `scripts_pub/attack_kyber768cbd_Buf_singletrace.jl`.
Then, run the attack again:
```
$ julia --project -t4 scripts_pub/attack_kyber768cbd_Buf_singletrace.jl
```

## generate (LaTex) Tables
Run the following code to generate LaTeX table source code, with the newly
produced single-trace attack success rates.
```
$ julia --project scripts_pub/h5result2latextable_multiboardsingletrace.jl
```
Then, paste the results (in `results/...Success_Rate.tex`) to a LaTeX editor
to view the updated attack result Tables.


## generate Figures




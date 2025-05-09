# GNU Make

.DELETE_ON_ERROR:

# rasterizing PDF figures (e.g. for README.md)
DPI=250
GS_OPTIONS=-dSAFER -dNOPAUSE -q -dBATCH -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dAlignToPixels=0 -r$(DPI) -sDEVICE=png16m
%.png: %.pdf
	gs $(GS_OPTIONS) -sOutputFile=$@ $<

results/%.pdf: scripts/%.tex
	pdflatex -halt-on-error -output-directory results $<
	while grep 'Rerun to get ' results/$*.log ; do pdflatex -output-directory results $< ; done

THREADOPT=-t4
#DATA_DIR=data


# this profiling and attack run requires about 25 GB file space (not counting JULIA_DEPOT_PATH)
option_1: instantiate results/SuccessRateTables.png results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png
#option_1: instantiate
#	julia --project scripts/downloaddata.jl
#	julia --project scripts/profiling_kyber768cbd.jl
#	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl
#	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP Encaps
#	$(MAKE) results/SuccessRateTables.png
#	$(MAKE) results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png

# more thrifty download and deletion order, requires only about 12 GB file space
option_2: instantiate
	julia --project scripts/downloaddata.jl --profiling
	julia --project scripts/profiling_kyber768cbd.jl
	julia --project scripts/deletedata.jl --profiling
	julia --project scripts/downloaddata.jl --attack
	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl
	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP Encaps
	$(MAKE) results/SuccessRateTables.png
	$(MAKE) results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png
	julia --project scripts/deletedata.jl --attack


# install and precompile all Julia dependencies of this project
instantiate:
	julia --project -e 'import Pkg; Pkg.instantiate()'

downloaddata: scripts/downloaddata.jl scripts/Traces-Os-pub-checksum.h5
	julia --project scripts/downloaddata.jl

# rules for building templates (profiling)

profiling: $(DK2_Templates)

$(DK2_profiling_dataset): scripts/downloaddata.jl scripts/Traces-Os-pub-profiling-checksum.h5
	julia --project scripts/downloaddata.jl --profiling

$(DK2_Templates): scripts/profiling_kyber768cbd.jl $(DK2_profiling_dataset)
	julia --project scripts/profiling_kyber768cbd.jl

delete_profiling_dataset: scripts/deletedata.jl scripts/Traces-Os-pub-profiling-checksum.h5
	julia --project scripts/deletedata.jl --profiling


# rules for producing attack results

attack: attack_keygen attack_encaps

attack_keygen: $(MS2_test_K_results)

attack_encaps: $(MS2_test_E_results)

$(MS2_attack_dataset): scripts/downloaddata.jl scripts/Traces-Os-pub-attack-checksum.h5
	julia --project scripts/downloaddata.jl --attack

$(MS2_test_K_results): scripts/attack_kyber768cbd_Buf_singletrace.jl $(prebuilt_Templates) \
			$(DK2_Templates_DIR)/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(MS2_test_K_DIR)traces_test_K_lanczos2_25_proc.h5 \
			$(MS2_test_K_DIR)S_test_K_proc.h5 $(MS2_test_K_DIR)Buf_test_K_proc.h5
	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP KeyGen

$(MS2_test_E_results): scripts/attack_kyber768cbd_Buf_singletrace.jl $(prebuilt_Templates) \
			$(DK2_Templates_DIR)/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(MS2_test_E_DIR)traces_test_E_lanczos2_25_proc.h5 \
			$(MS2_test_E_DIR)S_test_E_proc.h5 $(MS2_test_E_DIR)Buf_test_E_proc.h5
	julia --project $(THREADOPT) scripts/attack_kyber768cbd_Buf_singletrace.jl --targetOP Encaps

delete_attack_dataset: scripts/deletedata.jl scripts/Traces-Os-pub-attack-checksum.h5
	julia --project scripts/deletedata.jl --attack


# rules for building the tables and figures

results/KeyGen_Multi-Board_Single-Trace_Attack_Success_Rate.tex results/Encaps_Multi-Board_Single-Trace_Attack_Success_Rate.tex: scripts/h5result2latextable_multiboardsingletrace.jl $(MS2_test_K_results) $(MS2_test_E_results)
	julia --project scripts/h5result2latextable_multiboardsingletrace.jl

results/SuccessRateTables.pdf: results/KeyGen_Multi-Board_Single-Trace_Attack_Success_Rate.tex \
	                       results/Encaps_Multi-Board_Single-Trace_Attack_Success_Rate.tex

results/EMAdjustmentFigures.pdf: results/traces_and_XY_templates.png results/traces_and_XY_templates_EMadj.png \
	                         results/traces_and_X_templates.png  results/traces_and_X_templates_EMadj.png

results/traces_and_XY_templates.png results/traces_and_XY_templates_EMadj.png: scripts/figure_emadj_templates.jl \
			$(DK2_Templates_DIR)/Templates_XY_proc_nicv.001_POIe40-80_lanczos2.h5 \
			$(MS2_test_K_DIR)traces_test_K_lanczos2_25_proc.h5 $(MS2_test_K_DIR)XY_test_K_proc.h5
	julia --project $< --variable XY --output $@

results/traces_and_X_templates.png results/traces_and_X_templates_EMadj.png: scripts/figure_emadj_templates.jl \
			$(DK2_Templates_DIR)/Templates_X_proc_nicv.001_POIe40-80_lanczos2.h5 \
			$(MS2_test_K_DIR)traces_test_K_lanczos2_25_proc.h5 $(MS2_test_K_DIR)X_test_K_proc.h5
	julia --project $< --variable X --output $@

results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png: results/EMAdjustmentFigures.pdf
	gs $(GS_OPTIONS) -r500 -sOutputFile=results/EMAdjustmentFigures%d.png $<

tests:
	julia --project -e 'import Pkg; Pkg.test(["EMAlgorithm", "LeakageAssessment", "TemplateAttack"])'

Kyber768cbd.zip:
	git clone --recursive https://github.com/eric-cyp24/Kyber768cbd.jl Kyber768cbd
	cd Kyber768cbd && git submodule update
	rm -rf Kyber768cbd/.git* Kyber768cbd/packages/*/.git*
	zip -r $@ Kyber768cbd

install_figures: results/SuccessRateTables.png results/EMAdjustmentFigures1.png results/EMAdjustmentFigures2.png
	cp $+ scripts/

clean:
	rm -rf data/ results/






# directories and files for profiling

DK2_profile_DIR   = data/Traces/SOCKET_HPF/DK2/test_20241219/lanczos2_25/
DK2_Templates_DIR = data/Traces/SOCKET_HPF/DK2/test_20241219/lanczos2_25/Templates_POIe40-80/

DK2_profiling_dataset = $(DK2_profile_DIR)traces_lanczos2_25_proc.h5 \
					    $(DK2_profile_DIR)Buf_proc.h5 \
					    $(DK2_profile_DIR)XY_proc.h5 \
					    $(DK2_profile_DIR)S_proc.h5

DK2_Templates = $(DK2_Templates_DIR)/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			    $(DK2_Templates_DIR)/Templates_XY_proc_nicv.001_POIe40-80_lanczos2.h5 \
			    $(DK2_Templates_DIR)/Templates_X_proc_nicv.001_POIe40-80_lanczos2.h5


# directories and files for attacks

Pooled_DIR            = data/Traces/SOCKET_HPF/Pooled/Pooled_HPF/
MS2_test_K_DIR        = data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25_test_K/
MS2_test_K_result_DIR = data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25_test_K/Results/Templates_POIe40-80/
MS2_test_E_DIR        = data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25_test_E/
MS2_test_E_result_DIR = data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25_test_E/Results/Templates_POIe40-80/

prebuilt_Templates = \
			data/Traces/SOCKET_HPF/DK1/test_20241219/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/FN1/test_20241220/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/FN2/test_20241220/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/MS1/test_20241221/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/MS2/test_20241221/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/RS1/test_20241222/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			data/Traces/SOCKET_HPF/RS2/test_20241222/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN1_FN2_MS1_MS2_RS1/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN1_FN2_MS1_MS2_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN1_FN2_MS1_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN1_FN2_MS2_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN1_MS1_MS2_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_DK2_FN2_MS1_MS2_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK1_FN1_FN2_MS1_MS2_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5 \
			$(Pooled_DIR)DK2_FN1_FN2_MS1_MS2_RS1_RS2/lanczos2_25/Templates_POIe40-80/Templates_Buf_proc_nicv.004_POIe40-80_lanczos2.h5

MS2_attack_dataset = $(prebuilt_Templates) \
			$(MS2_test_K_DIR)traces_test_K_lanczos2_25_proc.h5 \
			$(MS2_test_K_DIR)S_test_K_proc.h5 \
			$(MS2_test_K_DIR)Buf_test_K_proc.h5 \
			$(MS2_test_E_DIR)traces_test_E_lanczos2_25_proc.h5 \
			$(MS2_test_E_DIR)S_test_E_proc.h5 \
			$(MS2_test_E_DIR)Buf_test_E_proc.h5

MS2_test_K_results = \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_DK1_test_20241219.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_DK2_test_20241219.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_FN1_test_20241220.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_FN2_test_20241220.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_MS1_test_20241221.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_MS2_test_20241221.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_RS1_test_20241222.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_RS2_test_20241222.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_MS2_RS1.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_MS2_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_RS1_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS2_RS1_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN2_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_FN1_FN2_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_K_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK2_FN1_FN2_MS1_MS2_RS1_RS2.h5

MS2_test_E_results = \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_DK1_test_20241219.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_DK2_test_20241219.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_FN1_test_20241220.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_FN2_test_20241220.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_MS1_test_20241221.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_MS2_test_20241221.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_RS1_test_20241222.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_RS2_test_20241222.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_MS2_RS1.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_MS2_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS1_RS1_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_FN2_MS2_RS1_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN1_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_DK2_FN2_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK1_FN1_FN2_MS1_MS2_RS1_RS2.h5 \
			$(MS2_test_E_result_DIR)marginalize_Buf_Result_with_Templates_POIe40-80_from_SOCKET_HPF_Pooled_Pooled_HPF_DK2_FN1_FN2_MS1_MS2_RS1_RS2.h5


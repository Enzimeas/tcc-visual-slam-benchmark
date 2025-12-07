#!/bin/bash


ORB_SLAM3_PATH="/home/enzi/Dev/ORB_SLAM3"
DATASETS_PATH="/home/enzi/UbuntuSharedVM/Datasets"
RESULTS_PATH="/home/enzi/UbuntuSharedVM/results"
VOCABULARY_FILE="$ORB_SLAM3_PATH/Vocabulary/ORBvoc.txt"
NUM_RUNS=5

EXECUTABLE_TUM="$ORB_SLAM3_PATH/Examples/Monocular/mono_tum"
EXECUTABLE_EUROc="$ORB_SLAM3_PATH/Examples/Monocular/mono_euroc"

declare -A DATASETS
DATASETS["euroc"]="MH_04_difficult MH_05_difficult V1_03_difficult V2_03_difficult"
DATASETS["kitti"]="00 01 03"
DATASETS["rover"]="garden_small_2024-01-13-winter garden_small_2024-05-29_1-day garden_small_2024-05-29_4-night"
DATASETS["tartanair"]="visual_endofworld visual_moon visual_westerndesert"
DATASETS["uzhfpv"]="outdoor_forward_1_snapdragon_with_gt outdoor_forward_3_snapdragon_with_gt outdoor_forward_5_snapdragon_with_gt"
DATASETS["tum"]="rgbd_dataset_freiburg1_desk rgbd_dataset_freiburg1_plant rgbd_dataset_freiburg1_rpy rgbd_dataset_freiburg1_xyz"



run_benchmark_tum() {
    local dataset_name="$1"
    local seq="$2"
    local settings_file="$3"
    
    echo "  -> Sequencia: $seq"
    local output_dir="$RESULTS_PATH/$dataset_name/$seq" && mkdir -p "$output_dir"
    
    local sequence_path=""
    if [ "$dataset_name" == "kitti" ]; then
        sequence_path="$DATASETS_PATH/$dataset_name/data_odometry_color/$seq"
    elif [ "$dataset_name" == "rover" ]; then
        sequence_path="$DATASETS_PATH/$dataset_name/$seq/pi_cam"
    else
        sequence_path="$DATASETS_PATH/$dataset_name/$seq"
    fi

    for i in $(seq 1 $NUM_RUNS); do
        echo "       - Rodada $i de $NUM_RUNS..."
        
        rm -f "KeyFrameTrajectory.txt"

        "$EXECUTABLE_TUM" "$VOCABULARY_FILE" "$settings_file" "$sequence_path"
        
        if [ -f "KeyFrameTrajectory.txt" ]; then
            mv "KeyFrameTrajectory.txt" "$output_dir/KeyFrameTrajectory_run${i}.txt"
        else
            echo -e "AVISO: KeyFrameTrajectory.txt não foi gerado na rodada $i."
        fi
    done
}


run_benchmark_euroc() {
    local dataset_name="euroc"
    local seq="$1"
    local settings_file="$ORB_SLAM3_PATH/Examples/Monocular/EuRoC.yaml"

    echo "  -> Sequência: $seq"
    local output_dir="$RESULTS_PATH/$dataset_name/$seq" && mkdir -p "$output_dir"
    local sequence_path="$DATASETS_PATH/$dataset_name/$seq"
    
    local timestamp_filename=""
    case "$seq" in
        "MH_04_difficult") timestamp_filename="MH04.txt" ;;
        "MH_05_difficult") timestamp_filename="MH05.txt" ;;
        "V1_03_difficult") timestamp_filename="V103.txt" ;;
        "V2_03_difficult") timestamp_filename="V203.txt" ;;
    esac
    local timestamp_path="$ORB_SLAM3_PATH/Examples/Monocular/EuRoC_TimeStamps/$timestamp_filename"
    local session_name="dataset-${seq}_mono"
    
    local keyframe_traj_file="kf_${session_name}.txt"

    for i in $(seq 1 $NUM_RUNS); do
        echo "       - Rodada $i de $NUM_RUNS..."
        
        rm -f "$keyframe_traj_file"
        
        "$EXECUTABLE_EUROc" "$VOCABULARY_FILE" "$settings_file" "$sequence_path" "$timestamp_path" "$session_name"
        

        if [ -f "$keyframe_traj_file" ]; then
            mv "$keyframe_traj_file" "$output_dir/KeyFrameTrajectory_run${i}.txt"
        else
            echo -e "AVISO: $keyframe_traj_file não foi gerado na rodada $i."
        fi
    done
}


mkdir -p "$RESULTS_PATH"
cd "$ORB_SLAM3_PATH" || { echo "ERRO: Pasta do orbslam3 não encontrada em '$ORB_SLAM3_PATH'!"; exit 1; }

if [ ! -f "$EXECUTABLE_TUM" ] || [ ! -f "$EXECUTABLE_EUROc" ]; then
    echo "ERRO: Executáveis do orbslam3 não encontrados."
    exit 1
fi




echo "EuRoC"
for seq in ${DATASETS["euroc"]}; do
   run_benchmark_euroc "$seq"
done


echo "KITTI"
for seq in ${DATASETS["kitti"]}; do
   if [ "$seq" == "03" ]; then
       settings="Examples/Monocular/KITTI03.yaml"
   else
       settings="Examples/Monocular/KITTI00-02.yaml"
   fi
   run_benchmark_tum "kitti" "$seq" "$settings"
done

echo "Rover"
settings_file="$DATASETS_PATH/rover/calibration/rover_calib.yaml"
for seq in ${DATASETS["rover"]}; do
   run_benchmark_tum "rover" "$seq" "$settings_file"
done

echo "TartanAir"
settings_file="$DATASETS_PATH/tartanair/tartanair_calib.yaml"
for seq in ${DATASETS["tartanair"]}; do
   run_benchmark_tum "tartanair" "$seq" "$settings_file"
done


echo "TUM"
settings_file="Examples/Monocular/TUM1.yaml"
for seq in ${DATASETS["tum"]}; do
   run_benchmark_tum "tum" "$seq" "$settings_file"
done

echo "UZH-FPV ---"
settings_file="$DATASETS_PATH/uzhfpv/outdoor_forward_calib_snapdragon/uzhfpv_calib.yaml"
for seq in ${DATASETS["uzhfpv"]}; do
    run_benchmark_tum "uzhfpv" "$seq" "$settings_file"
done


echo "FIM"
echo "Resultados salvos em: $RESULTS_PATH"

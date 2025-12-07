import os
import pandas as pd
from evo.tools import file_interface
from evo.core import sync
from evo.core import trajectory
from evo.core.metrics import APE, RPE, PoseRelation
from evo.tools.log import configure_logging
import copy

configure_logging(verbose=False, debug=False, silent=True)

# tum em 30 hz e euroc em 20 hz

def compute_all_metrics(traj_ref, traj_est, max_diff=0.01, rpe_delta=1):
    ref_sync, est_sync = sync.associate_trajectories(traj_ref, traj_est, max_diff)
    
    if len(ref_sync.timestamps) == 0:
        return None

    metrics = {}

    est_sync_aligned = copy.deepcopy(est_sync)
    
    R, t, s = est_sync_aligned.align(ref_sync, correct_scale=True)

    ape_metric = APE(PoseRelation.translation_part)
    ape_metric.process_data((ref_sync, est_sync_aligned))

    all_stats_ape = ape_metric.get_all_statistics()
    metrics["ATE_trans_rmse"] = all_stats_ape.get('rmse')

    est_sync_scaled_only = copy.deepcopy(est_sync)
    
    est_sync_scaled_only.scale(s)
    
    rpe_metric_trans = RPE(PoseRelation.translation_part, delta=rpe_delta)
    rpe_metric_trans.process_data((ref_sync, est_sync_scaled_only)) 
    all_stats_rpe_trans = rpe_metric_trans.get_all_statistics()
    metrics["RPE_trans_rmse"] = all_stats_rpe_trans.get('rmse')
    
    rpe_metric_rot = RPE(PoseRelation.rotation_angle_deg, delta=rpe_delta)
    rpe_metric_rot.process_data((ref_sync, est_sync_scaled_only))
    all_stats_rpe_rot = rpe_metric_rot.get_all_statistics()
    metrics["RPE_rot_rmse_deg"] = all_stats_rpe_rot.get('rmse')

    return metrics


def get_runs(folder, mast3rslam=True):
    if mast3rslam:
        prefix = "trajectory_run_"
    else:
        prefix = "KeyFrameTrajectory_run"
    return sorted([f for f in os.listdir(folder) if f.startswith(prefix) and f.endswith(".txt")])

def main():
    base_gt = "./Datasets"
    base_mast3r = "./Datasets/results_mast3rslam"
    base_orb = "./Datasets/results_orbslam3"

    datasets = ["euroc", "tum"]
    results = []

    for dataset in datasets:
        gt_root = os.path.join(base_gt, dataset)
        mast3r_root = os.path.join(base_mast3r, dataset)
        orb_root = os.path.join(base_orb, dataset)

        if not os.path.isdir(mast3r_root) or not os.path.isdir(orb_root):
            continue

        for seq in sorted(os.listdir(mast3r_root)):

            seq_mast3r = os.path.join(mast3r_root, seq)
            seq_orb = os.path.join(orb_root, seq)
            
            seq_gt = os.path.join(gt_root, seq)

            if not os.path.isdir(seq_mast3r) or not os.path.isdir(seq_orb) or not os.path.isdir(seq_gt):
                continue

            if dataset == "euroc":
                gt_file = os.path.join(seq_gt, "state_groundtruth_estimate0", "data.csv")
                gt_tum = os.path.join(seq_gt, "gt_tum.txt")
                if not os.path.isfile(gt_file):
                    continue

                if not os.path.isfile(gt_tum):
                    df = pd.read_csv(gt_file, delimiter=',')
                    df.columns = df.columns.str.strip()
                    df_tum = pd.DataFrame({
                        'stamp': df['#timestamp'],
                        'tx': df['p_RS_R_x [m]'], 'ty': df['p_RS_R_y [m]'], 'tz': df['p_RS_R_z [m]'],
                        'qx': df['q_RS_x []'], 'qy': df['q_RS_y []'], 'qz': df['q_RS_z []'], 'qw': df['q_RS_w []'],
                    })
                    df_tum.to_csv(gt_tum, sep=' ', index=False, header=False)
                gt_traj = file_interface.read_tum_trajectory_file(gt_tum)
            else: # tum
                gt_file = os.path.join(seq_gt, "groundtruth/groundtruth.txt")

                if not os.path.isfile(gt_file):
                    continue
                
                gt_traj = file_interface.read_tum_trajectory_file(gt_file)

            for i in range(1, 6):
                mast3r_file = os.path.join(seq_mast3r, f"trajectory_run_{i}.txt")
                orb_file = os.path.join(seq_orb, f"KeyFrameTrajectory_run{i}.txt")

                if dataset.lower() == "tum":
                    rpe_delta = 1
                else:
                    rpe_delta = 1
                
                if os.path.isfile(mast3r_file):
                    mast3r_traj = file_interface.read_tum_trajectory_file(mast3r_file)
                    mast3r_metrics = compute_all_metrics(gt_traj, mast3r_traj, rpe_delta=rpe_delta)
                    if mast3r_metrics:
                        results.append({
                            "Dataset": dataset, "Sequência": seq, "Run": i, "Algoritmo": "mast3rslam",
                            **mast3r_metrics
                        })

                if os.path.isfile(orb_file):
                    orb_traj = file_interface.read_tum_trajectory_file(orb_file)
                    orb_metrics = compute_all_metrics(gt_traj, orb_traj, rpe_delta=rpe_delta)
                    if orb_metrics:
                        results.append({
                            "Dataset": dataset, "Sequência": seq, "Run": i, "Algoritmo": "orbslam3",
                            **orb_metrics
                        })
                        
    if results:
        df = pd.DataFrame(results)
        os.makedirs('results', exist_ok=True)
        
        raw_results_path = 'results/comparacao_slam_extended.csv'
        df.to_csv(raw_results_path, index=False)
        
        metric_columns = ["ATE_trans_rmse", "RPE_trans_rmse", "RPE_rot_rmse_deg"]
        
        summary_df = df.groupby(["Dataset", "Sequência", "Algoritmo"])[metric_columns].agg(['mean', 'std'])
        
        summary_df.columns = ['_'.join(col).strip() for col in summary_df.columns.values]
        
        summary_path = 'results/comparacao_slam_summary.csv'
        summary_df.to_csv(summary_path)
                
        print(summary_df)

    else:
        print("Nenhum resultado encontrado para exportar.")

if __name__ == "__main__":
    main()

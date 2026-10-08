#!/bin/bash
#SBATCH --job-name=test_slurm
#SBATCH --output=result_%j.log
#SBATCH --ntasks=1
#SBATCH --time=00:02:00

echo "Job démarré sur le nœud : $(hostname)"
echo "ID du job : $SLURM_JOB_ID"
sleep 30
echo "Job terminé !"
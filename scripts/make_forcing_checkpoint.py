"""
Write a checkpoint for a ground-truth "forcing" model (atmos_gt_model / ocean_gt_model).

coupled_forecast*.py always loads `<model_dir>/tensorboard/checkpoints/<ckpt>` and calls
load_state_dict, even for diagnostic models whose weights are never used. This instantiates the
model from `<model_dir>/.hydra/config.yaml` and saves its (arbitrary) state dict in that location.

Example:
    python scripts/make_forcing_checkpoint.py models/atmos-forcing-model --gt-dataset /path/to/gt.zarr
"""
import argparse
import os

import torch as th
from hydra.utils import instantiate
from omegaconf import OmegaConf


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('model_path', help='forcing model directory containing .hydra/config.yaml')
    parser.add_argument('--gt-dataset', default=None, help='override model.gt_dataset (only needs to exist to build the model)')
    parser.add_argument('--checkpoint-name', default='epoch=0000-val_loss=0.0E+00.ckpt')
    args = parser.parse_args()

    cfg = OmegaConf.load(os.path.join(args.model_path, '.hydra', 'config.yaml'))
    if args.gt_dataset is not None:
        cfg.model.gt_dataset = args.gt_dataset
    # resolve data-dependent interpolations the same way coupled_forecast does
    cfg.model.enable_healpixpad = False
    cfg.model.input_channels = len(cfg.data.input_variables)
    cfg.model.output_channels = len(cfg.data.output_variables or cfg.data.input_variables)
    cfg.model.n_constants = len(cfg.data.constants or {})
    cfg.model.decoder_input_channels = int(cfg.data.get('add_insolation', 0))
    # resolve only the model section (the trainer section has interpolations that are unresolvable here)
    model_cfg = OmegaConf.create(OmegaConf.to_container(cfg.model, resolve=True))

    model = instantiate(model_cfg)
    out_dir = os.path.join(args.model_path, 'tensorboard', 'checkpoints')
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, args.checkpoint_name)
    th.save({'model_state_dict': model.state_dict()}, path)
    print(f'wrote {path}')


if __name__ == '__main__':
    main()

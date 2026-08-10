# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "coremltools==9.0",
#   "numpy==2.2.6",
# ]
# ///

"""Re-emit an ML Program package with FP16 compute and weight storage."""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
from coremltools.converters.mil.frontend.milproto.load import load as load_mil_program


def convert(source_path: Path, output_path: Path) -> None:
    source = ct.models.MLModel(str(source_path), skip_model_load=True)
    spec = source.get_spec()
    if spec.WhichOneof("Type") != "mlProgram":
        raise ValueError("Only ML Program .mlpackage models are supported")
    if source.weights_dir is None:
        raise ValueError("The source package does not contain an external weights directory")

    program = load_mil_program(
        spec,
        specification_version=spec.specificationVersion,
        file_weights_dir=source.weights_dir,
    )
    converted = ct.convert(
        program,
        source="milinternal",
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT16,
        skip_model_load=True,
    )

    converted.author = source.author
    converted.license = source.license
    converted.version = source.version
    converted.short_description = source.short_description
    for feature in spec.description.input:
        converted.input_description[feature.name] = feature.shortDescription
    for feature in spec.description.output:
        converted.output_description[feature.name] = feature.shortDescription

    output_path.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(output_path))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    convert(args.source.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()

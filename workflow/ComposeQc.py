# Use this script to tabulate simulation status for models in this batch.

from collections.abc import Generator
from pathlib import Path
import re
from argparse import ArgumentParser
import json

def check_one_energyplus_input_file(instance_idf_path: Path):
    # Returns exists, nonempty, filesize, energyplus_version, timesteps_per_hour, idd_validation_status, schedule_file_list, is_sizing_run
    # 
    exists = instance_idf_path.exists()
    nonempty = exists and instance_idf_path.stat().st_size > 0
    filesize = instance_idf_path.stat().st_size if exists else None
    energyplus_version = None
    timesteps_per_hour = None
    idd_validation_status = None
    schedule_file_list = []
    is_sizing_run = False

    model_content = instance_idf_path.read_text(errors="replace") if nonempty else None

    if not model_content:
        return exists, nonempty, filesize, energyplus_version, timesteps_per_hour, idd_validation_status, schedule_file_list, is_sizing_run
    
    # Typical version line in an IDF file looks like this:
    # Version,\r\n 9.5; !- Version Identifier
    # The version object can appear on any line in the model file. Use multiline flag to match it correctly.
    version_pattern = r'^\s*Version,\s*(?P<version>[^,;]*);'
    m_energyplus_version = model_content and re.search(version_pattern, model_content, re.MULTILINE)
    energyplus_version = m_energyplus_version['version'] if m_energyplus_version else None

    # Typical timestep line in an IDF file looks like this:
    # Timestep,\r\n 6; !- Number of Timesteps per Hour
    # The timestep object can appear on any line in the model file. Use multiline flag to match it correctly.
    timestep_pattern = r'^\s*Timestep,\s*(?P<timesteps_per_hour>[^,;]*);'
    m_timesteps_per_hour = model_content and re.search(timestep_pattern, model_content, re.MULTILINE)
    timesteps_per_hour = int(m_timesteps_per_hour['timesteps_per_hour']) if m_timesteps_per_hour else None

    # TODO: If EnergyPlus has an IDF validation tool, invoke it here. Not worth the effort otherwise.
    idd_validation_status = None

    # Search for SCHEDULE:FILE objects in the IDF file.
    schedule_pattern = r'^\s*SCHEDULE:FILE,\s*(?P<schedule_file>[^,;]*);'
    schedule_file_list = [m['schedule_file'] for m in re.finditer(schedule_pattern, model_content, re.MULTILINE)]
    # schedule_file_list = []
    
    # Search for SimulationControl object in the IDF file.
    # Typical pattern for a sizing run in an IDF file looks like this, where only the fourth input field matters:
    # SimulationControl,
    #   Yes or No,                     !- Do Zone Sizing Calculation
    #   Yes or No,                     !- Do System Sizing Calculation
    #   Yes or No,                     !- Do Plant Sizing Calculation
    #   Yes,                     !- Run Simulation for Sizing Periods
    #   No;                     !- Run Simulation for Weather File Run Periods
    input_field_line_pattern = r'^[ \t]*([^,;]*)[,;][ \t]*(?:![^\r\n]*)?$'
    sizing_run_pattern = (r'^\s*SimulationControl,'
                          + input_field_line_pattern
                          + input_field_line_pattern
                          + input_field_line_pattern
                          + r'\s*Yes;')
    is_sizing_run = bool(re.search(sizing_run_pattern, model_content, re.MULTILINE))

    return exists, nonempty, filesize, energyplus_version, timesteps_per_hour, idd_validation_status, schedule_file_list, is_sizing_run


def get_composed_files(scenario_root: Path) -> Generator[tuple[Path, str, str, str], None, None]:
    # Returns a list of composed files with the relative file path and metadata (labels)
    # Each element (tuple) contains 'relpath', 'cz', 'cohort', 'techid'

    # Implement the function to get composed files.
    # Composed files are expected to be under 'runs/**/instance.idf' relative to the scenario root.
    # Alternate pattern: runs/**/instance-hardsize.idf
    # Alternate pattern: runs/**/instance-size.idf. Used for a sizing run only.

    # Actually, modelkit rake compose creates instance.idf files;
    # modelkit rake hardsize creates instance-hardsize.idf files.

    for f in scenario_root.glob('runs/**/instance.idf'):
        relpath = f.relative_to(scenario_root)
        _, cz, cohort, techid, _ = relpath.parts
        yield (relpath.as_posix(), cz, cohort, techid)

    for f in scenario_root.glob('runs/**/instance-hardsize.idf'):
        relpath = f.relative_to(scenario_root)
        _, cz, cohort, techid, _ = relpath.parts
        yield (relpath.as_posix(), cz, cohort, techid)

    for f in scenario_root.glob('runs/**/instance-size.idf'):
        relpath = f.relative_to(scenario_root)
        _, cz, cohort, techid, _ = relpath.parts
        yield (relpath.as_posix(), cz, cohort, techid)

def get_composed_files_list(scenario_root: Path) -> list[tuple[Path, str, str, str]]:
    # Returns a list of composed files with the relative file path and metadata (labels)
    # Each element (tuple) contains 'relpath', 'cz', 'cohort', 'techid'
    return list(get_composed_files(scenario_root))

def gather_compose_batch_info(
    scenario_root: Path
) -> dict:
    # Implement the function to gather compose batch info.
    composed_files = get_composed_files_list(scenario_root)
    batch_info = {}
    for relpath, cz, cohort, techid in composed_files:
        key = relpath
        stats = check_one_energyplus_input_file(scenario_root / relpath)
        if key not in batch_info:
            batch_info[key] = [relpath, cz, cohort, techid, stats]
    
    return batch_info

def analyze_batch_info(scenarioInventoryPath: Path, batch_info: dict) -> dict:
    analysis_template = {
        "status": "Passed",

        "inventory": {
            "expectedModels": 4096,
            "actualModels": 4096,
            "missingModels": 0,
            "extraModels": 0,
            "tempDirectories": 0
        },

        "warnings": [],

        "errors": [],

        "scenarios": [
            {
            "scenarioId": "SWHC027",

            "expectedModels": 4096,

            "actualModels": 4096,

            "missingModels": [],

            "tempDirectories": 0
            }
        ]
    }
    analysis = {}
    countMissing = 0
    countExtra = 0
    for key, value in batch_info.items():
        relpath, cz, cohort, techid, stats = value
        exists, nonempty, filesize, energyplus_version, timesteps_per_hour, idd_validation_status, schedule_file_list, is_sizing_run = stats
        analysis[key] = {
            "exists": exists,
            "nonempty": nonempty,
            "filesize": filesize,
            "energyplus_version": energyplus_version,
            "timesteps_per_hour": timesteps_per_hour,
            "idd_validation_status": idd_validation_status,
            "schedule_file_list": schedule_file_list,
            "is_sizing_run": is_sizing_run
        }
        if not exists:
            countMissing += 1
        if exists and not nonempty:
            countExtra += 1
    analysis["countMissing"] = countMissing
    analysis["countExtra"] = countExtra
    return analysis

def create_markdown_summary(analysis: dict) -> str:
    markdown = "# Compose QC Summary\n\n"
    for scenario_id, scenario_analysis in analysis.items():
        markdown += f"## Scenario: {scenario_id}\n\n"
        markdown += f"- Missing Models: {scenario_analysis.get('countMissing', 0)}\n"
        markdown += f"- Extra Models: {scenario_analysis.get('countExtra', 0)}\n\n"
    return markdown

def main():
    parser = ArgumentParser()
    parser.add_argument('scenarioIndexPath', type=Path, default='scenario-index.json', nargs='?')
    parser.add_argument('measurePath', type=Path, default='.', nargs='?')        
    parser.add_argument('output_file', type=Path, default='composeQc.json', nargs='?')

    args = parser.parse_args()
    print("Starting Compose QC Analysis...")
    print(f"Scenario Index Path: {args.scenarioIndexPath}")
    print(f"Measure Path: {args.measurePath}")
    print(f"Output File: {args.output_file}")

    analysis = {}
    # Discover scenario subfolders from scenario-index.json
    with open(args.scenarioIndexPath, 'r') as f:
        scenarios = json.load(f)

    for scenario in scenarios:
        scenario_id = scenario.get("scenarioId")
        print(f"Analyzing scenario: {scenario_id}")
        scenarioPath = args.measurePath / scenario_id
        batch_info = gather_compose_batch_info(scenarioPath)
        scenarioAnalysis = analyze_batch_info(args.scenarioIndexPath, batch_info)
        analysis[scenario_id] = scenarioAnalysis
    print("Compose QC Analysis Complete.")

    print(f"Writing analysis results to: {args.output_file}")
    with open(args.output_file, 'w') as f:
        json.dump(analysis, f, indent=4)
    summary_file = args.output_file.with_suffix('.md')

    print(f"Writing markdown summary to: {summary_file}")
    summary = create_markdown_summary(analysis)
    summary_file = args.output_file.with_suffix('.md')
    with open(summary_file, 'w') as f:
        f.write(summary)

if __name__ == "__main__":
    main()

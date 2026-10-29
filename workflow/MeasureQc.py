# MeasureQc.py
# ├── verify root files
# ├── verify climates.csv
# ├── verify cohorts.csv
# ├── count files
# ├── detect scenarios
# └── emit measure-qc.json

from pathlib import Path
import json
#import re
import hashlib
import csv
import configparser
import argparse

KNOWN_RAKEFILE_HASHES_SHA256 = {
    'cd948e051252b0c0052e1780322828e719fa6b4c27550dd2ea35fe40dc03b012': 'v1', # original versions
    # e.g. \residential measures\SWHC049-03 SEER Rated AC HP\rakefile.rb
    # and \commercial measures\SWXX000-00 Measure Name\rakefile.rb
    'e81aa55516b6095aeeca0790fcfc9f8f9434198bbc19ae43477b374987585fb7': 'v2', # updated, with $repository_dir and other global variables for schedule:file portability
    # e.g. residential measures\SWXX000-00 Parameterized root files, 
}

KNOWN_QUERY_HASHES_SHA256 = {
    '58a1a45ad836fc5a1feb4aa8fd01f089f8cc2dc495e0c995ab8f7b3b8f55d313': 'v0.1', # old version, ...
    'ddf391977e01214e285a87d5d5e60c38444c7144c298e0da84c9489c9c741bd4': 'v0.2', # old version, not compatible with latest DNV data transformation tool
    'e24a69df751738553006a1bad0a1bf11a1ac5083c8262c6486726146e7e020e1': 'v0.3', # old version, ...
    '349512b4e377a2e4fd6e67c36b0fa33fc2bebded86dd20e6b7f9946a3c39e906': 'v0.4', # old version, ...
    '12afc7557effea53f84f7450238a6aee39c97b5c8034c9c03bdec30a1f51efae': 'v1', # version 2024-03-21
    '72fc3513a009e39bf35bdd2682b6f216fd9ed210c8d3844c2a93ac5eabd22d90': 'v2', # From residential measures/SWXX000-00 Parameterized root files only   
}

def read_and_count_csv(file_path, comment_char='#'):
    line_count = 0
    
    with open(file_path, mode='r', newline='', encoding='utf-8') as f:
        # Skip header
        next(f)
        # Filter out lines that start with the comment character or are blank
        filtered_lines = (line for line in f if line.strip() and not line.startswith(comment_char))
        
        # Pass the filtered lines into the csv reader
        reader = csv.reader(filtered_lines)
        
        for row in reader:
            line_count += 1
            # Process your row here if needed
            # print(row)
            
    return line_count

def read_climates(file_path, comment_char='#'):
    # Return a list of climate names

    # Typical climates file has these columns:
    # skip,climate,weather_file,climate_zone,codes_file
    
    climates = []
    
    with open(file_path, mode='r', newline='', encoding='utf-8') as f:
        
        # Skip header row
        next(f)

        # Filter out lines that start with the comment character or are blank
        filtered_lines = (line for line in f if line.strip() and not line.startswith(comment_char))
        
        # Pass the filtered lines into the csv reader
        reader = csv.reader(filtered_lines)
        
        # Read each row and collect climates
        for row in reader:
            if len(row) < 2:
                continue
            climates.append(row[1])
            
    return climates

def read_cohorts(file_path, comment_char='#'):
    # Return a list of cohort names

    # Typical cohorts file has these columns:
    # skip,cohort,root,<codes_parameter1>,<codes_parameter2>,...
    
    cohorts = []
    
    with open(file_path, mode='r', newline='', encoding='utf-8') as f:
        
        # Skip header row
        next(f)

        # Filter out lines that start with the comment character or are blank
        filtered_lines = (line for line in f if line.strip() and not line.startswith(comment_char))
        
        # Pass the filtered lines into the csv reader
        reader = csv.reader(filtered_lines)
        
        # Read each row and collect climates
        for row in reader:
            if len(row) < 2:
                continue
            cohorts.append(row[1])
            
    return cohorts


def read_cases(file_path, comment_char='#'):
    # Return a list of case names

    # Typical cohorts file has these columns:
    # #skip,case_name,<case_parameter1>,<case_parameter2>,...
    
    cases = []
    
    with open(file_path, mode='r', newline='', encoding='utf-8') as f:
        
        # Skip header row
        next(f)

        # Filter out lines that start with the comment character or are blank
        filtered_lines = (line for line in f if line.strip() and not line.startswith(comment_char))
        
        # Pass the filtered lines into the csv reader
        reader = csv.reader(filtered_lines)
        
        # Read each row and collect climates
        for row in reader:
            if len(row) < 2:
                continue
            cases.append(row[1])
            
    return cases

from enum import Enum
class QcStatus(Enum):
    PASSED = 'passed'
    FAILED = 'failed'

class QcSeverity(Enum):
    ERROR = 'error'
    WARNING = 'warnings'
    INFO = 'info'
    NONE = 'none'

SEVERITY_ICON = {
    QcSeverity.ERROR: "❌",
    QcSeverity.WARNING: "⚠️",
    QcSeverity.INFO: "ℹ️",
    QcSeverity.NONE: "✅"
}

def check_object(id: str, severity: QcSeverity = QcSeverity.NONE, passed: bool = True, message: str = ""):
    return {
        "id": id,
        "severity": severity.value,
        "passed": passed,
        "message": message
    }

def check_deer_measure_folder_consistency(
        measureDirectory: Path
        ):
    # Create placeholders for output objects
    success = True
    checks = []

    result = {
        "measureName": (measureDirectory.relative_to(measureDirectory.parents[1])).as_posix(),
        "status": "Passed",
        "errors": [],
        "warnings": [],
        "checks": [],
        "inventory": {
            "fileCount": None,
            "totalBytes": None,
            "scenarioCount": None,
            "rakefileVersion": None,
            "hasReadme": False,
            "countExtraFiles": 0,
            "countExtraFolders": 0
        },
        "scenarios": [
        ],
        "max-workers": 1
    }

    scenario0 = {
        "scenarioId": Path("."), # Name of the subfolder, e.g. SWHC031__Ex
        "climates": "Fail", # Does the climates file exist, and is it consistent with expected patterns? Pass/Fail
        "queryVersion": None, 
        "cohorts": "Fail", 
        "climateCount": 0, # How many climate zones are active in the climates file? There should be 16 in commercial measures; for SFm building type, special rules apply based on vintage.
        "cohortCount": 0, # How many active cohorts are listed in the cohorts file?
        "caseCount": 0, # How many CSV files exist under the cases folder? There should be one per active cohort.
        "extraCases": 0, # How many CSV files under the cases folder are not linked to an active cohort? These will have no effect.
        "simulationCount": 0 # How many simulations will be run? This is the product of climateCount * cohortCount * caseCount
    }

    sector = None
    if "commercial measures" in measureDirectory.parts:
        sector = 'commercial'
    elif "residential measures" in measureDirectory.parts:
        sector = 'residential'
    else:
        success = False

    # Does the global.pxv file exist, and is it consistent with expected patterns? Pass/Fail
    if not (measureDirectory/'global.pxv').exists():
        checks.append(check_object(id='global.pxv',severity=QcSeverity.ERROR,passed=False,message="Missing file global.pxv"))
    else:
        checks.append(check_object(id='global.pxv',severity=QcSeverity.NONE,passed=True,message="Found file global.pxv"))

    # Does the .modelkit-config file exist? Is it showing the expected EnergyPlus version depending on residential/commercial?
    # TODO: water heater measures may expect different energyplus version
    # TODO: update this logic if prototypes are updated to target a different EnergyPlus version
    if not (measureDirectory/'.modelkit-config').exists():
        checks.append(check_object(
            id='.modelkit-config',severity=QcSeverity.ERROR,passed=False,message='Missing file .modelkit-config'))
    else:
        modelkitConfig = (measureDirectory/'.modelkit-config')
        # Typically, .modelkit-config files start with an unnamed section.
        # In Python >= 3.13, configparser can accept unnamed section.
        # In Python < 3.13, we need to insert default section header at the beginning of the file.
        modelkitConfigText = '[DEFAULT]\n' + modelkitConfig.read_text()
        # Read the config file and look for the engine value under section 'energyplus-run', key 'engine'
        # The value should be the path to the EnergyPlus installation folder and shows which version of EnergyPlus is used for this measure.
        config  = configparser.ConfigParser(inline_comment_prefixes=('#'))
        #config.read(modelkitConfig)
        config.read_string(modelkitConfigText)
        if 'energyplus-run' not in config or 'engine' not in config['energyplus-run']:
            checks.append(check_object(
                id='.modelkit-config',severity=QcSeverity.ERROR,passed=False,
                message='.modelkit-config missing property [energyplus-run].engine'))
        else:
            engine = config['energyplus-run']['engine']
            if not ((sector == 'commercial' and engine.find("22-2-0") > 0) 
                or (sector == 'residential' and engine.find("9-5-0") > 0)):
                checks.append(check_object(
                    id='.modelkit-config',severity=QcSeverity.WARNING,passed=True,
                    message=f'.modelkit-config uses unrecognized combination sector = {sector}, engine = {engine}'))
            else:
                checks.append(check_object(
                    id='.modelkit-config',severity=QcSeverity.INFO,passed=True,
                    message=f'.modelkit-config uses sector = {sector}, engine = {engine}'))
        if 'DEFAULT' not in config or 'max-workers' not in config['DEFAULT']:
            checks.append(check_object(
                id='.modelkit-config',severity=QcSeverity.ERROR,passed=False,
                message='.modelkit-config missing property [DEFAULT].max-workers'))
        else:
            max_workers = config['DEFAULT']['max-workers']
            if not max_workers.isdigit() or int(max_workers) <= 0:
                checks.append(check_object(
                    id='.modelkit-config',severity=QcSeverity.WARNING,passed=True,
                    message=f'.modelkit-config has invalid value for [DEFAULT].max-workers: {max_workers}'))
            else:
                checks.append(check_object(
                    id='.modelkit-config',severity=QcSeverity.INFO,passed=True,
                    message=f'.modelkit-config has valid value for [DEFAULT].max-workers: {max_workers}'))
                result['max-workers'] = int(max_workers)

    # rakefile and rakefileVersion
    rakefile = measureDirectory/'rakefile.rb'
    rakefileVersion = None
    # Does the rakefile exist?
    if not rakefile.exists():
        checks.append(check_object(
            id='rakefile.rb',severity=QcSeverity.ERROR,passed=False,
            message='missing file rakefile.rb'))
    else:
        # Is the rakefile version recognized?
        # (Recognized = exact match for one of the versions known to the author of this script)
        hash = hashlib.sha256(rakefile.read_bytes()).hexdigest().lower()
        rakefileVersion = KNOWN_RAKEFILE_HASHES_SHA256.get(hash,'unrecognized')
        if rakefileVersion == 'unrecognized':
            checks.append(check_object(
                id='rakefile.rb',severity=QcSeverity.WARNING,passed=False,
                message=f'rakefile.rb unrecognized version with sha256 hash {hash[0:8]} ...'))
        else:
            checks.append(check_object(
                id='rakefile.rb',severity=QcSeverity.INFO,passed=True,
                message=f'rakefile.rb found matching version {rakefileVersion}'))

    # Is there a README.md file? (optional)
    # The name is flexible (capitalization, file extension). More than one file could match.
    hasReadme = False
    readmeName = None
    readmeList = list(measureDirectory.glob("README.*"))
    if not readmeList:
        checks.append(check_object(
                id='README',severity=QcSeverity.INFO,passed=True,
                message='No README file found'))
    else:
        hasReadme = True
        readmeName = readmeList[0].name
        checks.append(check_object(
            id='README',severity=QcSeverity.INFO,passed=True,
            message=f'Detected readme file: {readmeName}'))

    extraFiles = []
    # TODO: count extra files not alread detected above
    for f in measureDirectory.iterdir():
        if (f.is_dir() or f.name.upper().startswith('README')
            or f.name in ['global.pxv', 'rakefile.rb', '.modelkit-config']):
            continue
        extraFiles.append(f.name)
    result['inventory']['extraFiles'] = extraFiles
    if not extraFiles:
        checks.append(check_object(
            id='extraFiles',severity=QcSeverity.INFO,passed=True,
            message=f'No extra files found at measure level'))
    else:
        checks.append(check_object(
            id='extraFiles',severity=QcSeverity.INFO,passed=True,
            message=f'Detected {len(extraFiles)} extra files'))

    scenarios = []
    extraFolders = []
    # How many scenarios exist? Each scenario follows the pattern of subfolder that has a nested folder 'cases'.
    for subfolder in measureDirectory.iterdir():
        if not subfolder.is_dir():
            continue
        cases = subfolder / 'cases'
        if cases.exists() and cases.is_dir():
            scenarios.append(subfolder)
        else:
            extraFolders.append(subfolder)
    if not scenarios:
        checks.append(check_object(
            id='scenarios',severity=QcSeverity.ERROR,passed=False,
            message=f'No scenarios (subfolders) found. The measure must have at least one subfolder'))
    else:
        checks.append(check_object(
            id='scenarios',severity=QcSeverity.INFO,passed=True,
            message=f'Detected {len(scenarios)} scenarios (subfolders)'))

    checks.append(check_object(
        id='extraFolders',severity=QcSeverity.INFO,passed=True,
        message=f'Detected {len(extraFolders)} extra subfolders'))

    result['inventory']['countScenarios'] = len(scenarios)
    result['inventory']['countExtraFolders'] = len(extraFolders)

    for (i, subfolder) in enumerate(scenarios):
        scenario1 = scenario0.copy()

        # subfolder
        scenario1['scenarioId'] = subfolder.relative_to(measureDirectory).as_posix()
        scenarioName = subfolder.relative_to(measureDirectory).name

        # climates and climateCount
        climates_file = subfolder/'climates.csv'
        climates = []
        if not (climates_file.exists() and climates_file.is_file()):
            checks.append(check_object(
                id=f'scenario{i}/climates.csv',severity=QcSeverity.ERROR,passed=False,
                message=f'Missing climates.csv in scenario `{scenarioName}`'))
        else:
            try:
                # countClimates: Skip header row; count rows of data that are not blank or start with comment symbol, '#'.
                climateCount = read_and_count_csv(climates_file)
                scenario1['climateCount'] = climateCount
                climates = read_climates(climates_file)
                if climateCount == 0:
                    scenario1['climates'] = 'Fail'
                    checks.append(check_object(
                        id=f'scenario{i}/climates.csv',severity=QcSeverity.ERROR,passed=False,
                        message=f'climates.csv has no active climates in scenario `{scenarioName}`'))
                else:
                    scenario1['climates'] = 'Pass'
                    checks.append(check_object(
                        id=f'scenario{i}/climates.csv',severity=QcSeverity.INFO,passed=True,
                        message=f'climates.csv has {climateCount} active climates in scenario `{scenarioName}`'))
            except:
                checks.append(check_object(
                    id=f'scenario{i}/climates.csv',severity=QcSeverity.ERROR,passed=False,
                    message=f'Could not parse climates.csv in scenario `{scenarioName}`'))

        # query and queryVersion
        query = subfolder/'query.txt'
        if not (query.exists() and query.is_file()):
            checks.append(check_object(
                id=f'scenario{i}/query.txt',severity=QcSeverity.ERROR,passed=False,
                message=f'Missing query.txt in scenario `{scenarioName}`'))
        else:
            # Check against reference query file expected by data transformation script
            if sector == 'commercial':
                pass
            elif sector == 'residential':
                pass
            # Does the scenario/query.txt file match the version expected by DNV data transformation scripts?
            hash = hashlib.sha256(query.read_bytes()).hexdigest().lower()
            queryVersion =  KNOWN_RAKEFILE_HASHES_SHA256.get(hash,'unrecognized')
            scenario1['queryVersion'] = queryVersion
            if queryVersion == 'unrecognized':
                checks.append(check_object(
                    id=f'scenario{i}/query.txt',severity=QcSeverity.WARNING,passed=True,
                    message=f'query.txt version unrecognized with sha256 hash {hash[0:8]}... in scenario `{scenarioName}`'))
            else:
                checks.append(check_object(
                    id=f'scenario{i}/query.txt',severity=QcSeverity.INFO,passed=True,
                    message=f'query.txt found matching version {queryVersion} in scenario `{scenarioName}`'))

        # cohorts and cohortCount
        # Does the cohorts file exist, and is it consistent with the expected patterns? Pass/Fail
        cohorts_file = subfolder / 'cohorts.csv'
        cohorts = []
        if not(cohorts_file.exists() and cohorts_file.is_file()):
            checks.append(check_object(
                id=f'scenario{i}/cohorts.csv',severity=QcSeverity.ERROR,passed=False,
                message=f'Missing cohorts.csv in scenario `{scenarioName}`'))
        else:
            # TODO: we could validate that code requirement lookup columns are present and populated correctly as a function of prototype.
            # For most prototypes, the typical code lookup columns can be found by way of example in one of the reference measures.
            # However, creating and maintaining a list of code lookup columns is beyond the scope of work for developing this script.
            # If such a list becomes available, then update the logic here.
            try:
                cohortCount = read_and_count_csv(cohorts_file)
                # TODO: collect cohort names into a list for cross-check against files like 'cases/<cohort>.csv'
                scenario1['cohortCount'] = cohortCount
                print(f'cohort count: {cohortCount}')

                if cohortCount == 0:
                    checks.append(check_object(
                        id=f'scenario{i}/cohorts.csv',severity=QcSeverity.ERROR,passed=False,
                        message=f'cohorts.csv has no active cohorts in scenario `{scenarioName}`'))
                else:
                    checks.append(check_object(
                        id=f'scenario{i}/cohorts.csv',severity=QcSeverity.INFO,passed=True,
                        message=f'cohorts.csv has {cohortCount} active cohorts in scenario `{scenarioName}`'))
                    cohorts = read_cohorts(cohorts_file)
            except:
                checks.append(check_object(
                    id=f'scenario{i}/cohorts.csv',severity=QcSeverity.ERROR,passed=False,
                    message=f'Could not parse cohorts.csv in scenario `{scenarioName}`'))

        # caseCount and extraCases
        caseCount = 0
        casesFolder = subfolder / 'cases'
        cases = {cohort: [] for cohort in cohorts}
        if not(casesFolder.exists() and casesFolder.is_dir()):
            checks.append(check_object(
                id=f'scenario{i}/cases',severity=QcSeverity.ERROR,passed=False,
                message=f'Missing cases folder in scenario `{scenarioName}`'))
        else:
            for caseFile in casesFolder.glob('*.csv'):
                cohortName = caseFile.stem
                print(f'Found case file: `{cohortName}` in scenario `{scenarioName}`')
                caseCount += 1
            # TODO: check if caseFile.name is an active cohort, else count it toward extraCases
            # This is not critical.
            #if caseFile.name in cohortsList: pass
            if caseCount == 0:
                checks.append(check_object(
                    id=f'scenario{i}/cases',severity=QcSeverity.ERROR,passed=False,
                    message=f'cases folder has {caseCount} csv files in scenario `{scenarioName}`'))
            else:
                checks.append(check_object(
                    id=f'scenario{i}/cases',severity=QcSeverity.INFO,passed=True,
                    message=f'cases folder has {caseCount} csv files in scenario `{scenarioName}`'))
                cases_this_cohort = read_cases(casesFolder / f'{cohortName}.csv')
                cases[cohortName] = cases_this_cohort

        simulationCount = cohortCount * caseCount * climateCount
        scenario1['caseCount'] = caseCount
        scenario1['simulationCount'] = simulationCount
        result['scenarios'].append(scenario1)

        # Check the length of file paths for models that would be composed.
        # The pattern for composed model file paths could be something like:
        # composed_model_path = f'{scenario_name} /
        #                       'runs' /
        #                       f'{climate}' /
        #                       f'{cohort_name}' /
        #                       f'{case_name}' /
        #                       f'instance.idf'
        # energy_plus_outputs = composed_model_path.parent / 'instance-out.sql'
        # Check if the length of composed_model_path exceeds a certain limit (e.g., 255 characters)
        # TODO: Confirm limits and annotate path patterns for hardsized models
        path_length_limit = 255
        for climate in climates:
            for cohort in cohorts:
                for case in cases[cohort]:
                    composed_model_path = subfolder / 'runs' / f'{climate}' / f'{cohort}' / f'{case}' / 'instance.idf'
                    if len(str(composed_model_path)) > path_length_limit:
                        checks.append(check_object(
                            id=f'scenario{i}/path_length',severity=QcSeverity.WARNING,passed=False,
                            message=f'Composed model path exceeds 255 characters: `{composed_model_path}`'))

    success = True
    warnings = []
    errors = []
    for check in checks:
        if not check['passed']:
            success = False
        if check['severity'] == QcSeverity.WARNING.value:
            warnings.append(check['message'])
        if check['severity'] == QcSeverity.ERROR.value:
            errors.append(check['message'])
    result['status'] = 'Passed' if success else 'Failed'
    result['checks'] = checks
    result['warnings'] = warnings
    result['errors'] = errors

    # Prepare inventory summary
    all_files = [
        f for f in measureDirectory.rglob("*")
        if f.is_file()
    ]

    result["inventory"] = {
        "fileCount": len(all_files),
        "totalBytes": sum(f.stat().st_size for f in all_files),
        "scenarioCount": len(scenarios),
        "rakefileVersion": rakefileVersion,
        "hasReadme": hasReadme,
        "countExtraFiles": len(extraFiles),
        "countExtraFolders": len(extraFolders)
    }
    return result

def write_json(result, output_directory: Path = "."):
    # Output the measure QC status file
    outputFile = output_directory/'measure-qc.json'
    json.dump(result, outputFile.open('w'), indent=2)

    # Output the scenario subfolder index file
    scenarioIndex = output_directory/'scenario-index.json'
    json.dump(result['scenarios'], scenarioIndex.open('w'), indent=2)

def write_markdown_report(result, output_path: Path = '.'):
    lines = []

    status_icon = "✅" if result["status"] == "Passed" else "❌"

    lines.append("# Measure QC")
    lines.append("")
    lines.append(f"## Overall Result")
    lines.append("")
    lines.append(f"{status_icon} **{result['status']}**")
    lines.append("")

    lines.append("## Errors")
    lines.append("")
    for item in result["errors"]:
        lines.append(f"- ❌ {item}")
    lines.append("")

    if result["warnings"]:
        lines.append("## Warnings")
        lines.append("")
        for item in result["warnings"]:
            lines.append(f"- ⚠️ {item}")
        lines.append("")

    lines.append("## QC Checks")
    lines.append("")
    lines.append("| Check | Result |")
    lines.append("|---------|---------|")

    for check in result["checks"]:
        icon = SEVERITY_ICON[QcSeverity(check['severity'])]
        lines.append(
            f"| {check['message']} | {icon} |"
        )

    lines.append("")

    inventory = result["inventory"]

    lines.append("## Inventory")
    lines.append("")
    lines.append(f"- Scenario count: {inventory['scenarioCount']}")
    lines.append(f"- Total file count: {inventory['fileCount']}")
    lines.append(f"- Total bytes: {inventory['totalBytes']:,}")
    lines.append(f"- Max workers: {result['max-workers']}")
    lines.append("")

    lines.append("## Scenarios")
    lines.append("")
    lines.append("| Scenario | Climates | Cohorts | Cases | Simulations |")
    lines.append("|-----------|-----------|-----------|-----------|-----------|")

    for scenario in result["scenarios"]:
        lines.append(
            "| "
            f"{scenario['scenarioId']} | "
            f"{scenario['climateCount']} | "
            f"{scenario['cohortCount']} | "
            f"{scenario['caseCount']} | "
            f"{scenario['simulationCount']} |"
        )

    lines.append("")

    Path(output_path).write_text(
        "\n".join(lines),
        encoding="utf-8"
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('measureDirectory', type=Path)
    parser.add_argument('outputDirectory', type=Path)
    args = parser.parse_args()
    result = check_deer_measure_folder_consistency(args.measureDirectory)
    write_json(result, args.outputDirectory)
    write_markdown_report(result, args.outputDirectory/'measure-qc.md')

if __name__ == "__main__":
    main()
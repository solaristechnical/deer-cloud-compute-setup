# Compatible with Windows PowerShell 5.1 and PowerShell 7.
function Update-WorkflowRepository {
    param(
        [string]$RepoDir = "C:\DEER\deer-cloud-compute-setup"
    )

    if (-not (Test-Path "$RepoDir\.git")) {
      # while repository is private, use an authorized github deploy key to clone the repository.
      git clone git@github.com:simularis/deer-cloud-compute-setup.git $RepoDir
      # After the repository is public, switch to this:
      #git clone https://github.com/simularis/deer-cloud-compute-setup.git $RepoDir
    }
    else {
        git -C $RepoDir fetch origin
        git -C $RepoDir checkout main
        git -C $RepoDir reset --hard origin/main
        git -C $RepoDir clean -fd
    }
    $WorkflowCommit = git -C $RepoDir rev-parse HEAD
    Write-Host "WorkflowCommit: $WorkflowCommit"
}

# Caution: this step will always fetch the latest from deer-cloud-compute-setup.
# Remove this step after initial testing.
Write-Host "Checking out workflow repository ..."
Update-WorkflowRepository

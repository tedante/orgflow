# 🛠️ Instructor Guide: GitHub Organization & Repository Automation

This guide covers the prerequisites and step-by-step instructions for running the automation scripts to onboard students and provision private repository environments.

## 📋 Prerequisites (Do this First)

Before running either script, the instructor's local machine must have the GitHub CLI installed and authenticated with administrative organization access.

1. **Install GitHub CLI**:
   Open your terminal and install the CLI tool:
   ```bash
   brew install gh
   
2. **Authenticate with GitHub**:
   Link your GitHub account by running:
   ```bash
   gh auth login
      *Follow the interactive terminal prompts to log in via your browser.*

3. **Elevate Organization Permissions**:
   Explicitly grant the tool permission to manage organization resources:
   ```bash
   gh auth refresh -h github.com -s admin:org
   
---

## 👤 Step 1: Onboarding Students (`invite.sh`)

This script ensures the target cohort team is created in the organization and invites new students to join the organization as direct members assigned to that team.

### 1. Configuration
Open the `invite.sh` file in your preferred text editor and customize the parameters at the top of the file:
* **`USERS`**: List the exact GitHub usernames of the new students, separated by spaces.
* **`ORG`**: Specify your target GitHub Organization name.
* **`TEAM_NAME`**: Set your specific cohort tracker ID (e.g., `hck-100`).

### 2. Usage
Open your computer terminal, navigate to the folder containing your script, and run the file by typing the following command in your terminal:
```bash
bash invite.sh

---

## 🚀 Step 2: Bulk Assignment Provisioning (`create-repo.sh`)

This script creates private individual student repositories from a template repository, sets up isolated write access for each student, assigns reviewers, schedules milestones with deadlines, and initializes dedicated Feedback Pull Requests.

### 1. Configuration
Open the `create-repo.sh` file in your text editor and customize the parameters at the top of the file:
* **`USERS`**: Add the GitHub usernames of the active student cohort.
* **`REVIEWERS`**: Add the usernames of the instructors or TAs grading the work.
* **`TEAM_NAME`**: Set the cohort identifier (e.g., `FSJS-STUDENTS`). This will prefix each student's repository name to keep the organization view searchable and clean.
* **`TEMPLATES`**: Update the template source path and its target assignment submission deadline.

### 2. Usage
Open your computer terminal, navigate to the folder containing your script, and run the file by typing the following command in your terminal:
```bash
bash create-repo.sh
`
I have saved this to the workspace as `instructions.md` and provided the raw syntax block above. This will keep all your formatting perfectly preserved when you copy it! Let me know if you need any other additions.
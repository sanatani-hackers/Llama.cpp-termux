# Llama.cpp-termux Documentation

## System Prerequisites

- A supported Android device with Termux installed.
- Adequate free disk space for downloading and building the code.
- Android NDK installed for building from source.

## Using main.sh

To run `main.sh`, follow these steps:

1. **Ensure you have the following dependencies installed:**
   - Git
   - Required packages from Termux (you can use the command `apt install package-name`)

2. **Clone the repository (if not already done):**
   ```bash
   git clone https://github.com/sanatani-hackers/Llama.cpp-termux.git
   cd Llama.cpp-termux
   ```

3. **Make the script executable:**
   ```bash
   chmod +x main.sh
   ```

4. **Run the script:**
   ```bash
   ./main.sh
   ```
   This will initiate the setup and run the necessary commands.

5. **Follow on-screen instructions** for any additional configurations needed during the execution.

## Manual Build Instructions

### For CPU Builds:
1. Install necessary libraries and packages:
   ```bash
   apt install <dependencies>
   ```
2. Build the code:
   ```bash
   make build_cpu
   ```
3. Execute the binary:
   ```bash
   ./bin/lama_cpu
   ```

### For GPU Builds:
1. Install GPU dependencies:
   ```bash
   apt install <gpu_dependencies>
   ```
2. Build the code:
   ```bash
   make build_gpu
   ```
3. Run the GPU version:
   ```bash
   ./bin/lama_gpu
   ```

## Troubleshooting

- **Problem:** "Error: Dependency not found."
  **Solution:** Ensure all dependencies are properly installed and up-to-date.

- **Problem:** "Build fails."
  **Solution:** Check the error messages for hints; it may require adjusting the build commands or paths.

- **Problem:** "Execution error."
  **Solution:** Verify that the required runtime libraries are accessible and that your setup meets the prerequisites.
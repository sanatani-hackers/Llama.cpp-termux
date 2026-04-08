# Llama.cpp for Termux

## Overview
This repository focuses on utilizing Large Language Models (LLMs) with `main.sh` to manage various operations.

## What `main.sh` Does
`main.sh` is the main script that orchestrates the execution of LLM operations in Termux. It provides a user-friendly interface to manage different tasks related to LLMs.

## How to Run `main.sh`
To run the script, open your Termux terminal and execute the following command:
```bash
bash main.sh
```
Make sure you have the necessary permissions to execute the script.

## Menu Options
Once you run `main.sh`, you will be presented with 7 menu options, each corresponding to a different operation:

1. **Option 1: Load Model**  
   Load a Large Language Model into memory for operations.
2. **Option 2: Sample Text**  
   Generate sample text based on the loaded model's parameters.
3. **Option 3: Fine-Tune Model**  
   Fine-tune the loaded model with custom datasets.
4. **Option 4: Evaluate Model**  
   Run evaluations on the model's performance.
5. **Option 5: Save Model**  
   Save the current state of the model back to disk.
6. **Option 6: Manage Data**  
   Handle datasets used for training and testing the model.
7. **Option 7: Exit**  
   Exit the menu and terminate the script.

## Example Hardware Profile Output
When you run the script on your hardware, you can see the following output:
```
Processor: Intel Core i7-9750H
RAM: 16GB
GPU: NVIDIA GTX 1650

Model loaded: LLAma-2
``` 

## Quick Reference for Common Operations
- To load a model, select **Option 1**.
- To generate text, use **Option 2**.
- Always save your changes using **Option 5** before exiting.
- For fine-tuning, ensure you have sufficient RAM and a compatible dataset.

This README is dedicated solely to operations related to LLMs and the functionalities provided by `main.sh`. 

---

---
title: "Local dictation: Do I need an NVIDIA graphics card?"
description: "WhisPaste can use Vulkan, Metal or your CPU. Check the hardware requirements and find out when the optional CUDA pack applies."
date: 2026-10-16
---

Do you need an NVIDIA graphics card to dictate locally on your computer? With WhisPaste, the answer is no. The app also supports AMD and Intel graphics, and it can transcribe on the processor when no usable GPU is available. Before considering new hardware, take a look at the computer you already have.

## Start with the requirements

You need a 64-bit processor and free disk space for the app and its speech models; 8 GB of RAM is recommended. Supported systems are Windows 10 or later, Linux, and macOS 12 Monterey or later on Apple Silicon.

On the Mac there is one restriction: WhisPaste is an Apple Silicon build there. Older processors without AVX2 work too, provided they meet the other system requirements.

## AMD, Intel and Apple are supported too

On Windows and Linux, WhisPaste uses Vulkan for GPU acceleration. The same build works with NVIDIA, AMD and Intel graphics, provided a working Vulkan driver is available.

Intel integrated graphics can also do the processing if the driver supports Vulkan. You do not need a separate graphics card for that. On Apple Silicon, acceleration uses Metal, with the processor and graphics sharing unified memory.

## CUDA is an additional option

You do not need to install a CUDA toolkit to use GPU acceleration through Vulkan. If you have an NVIDIA RTX or GTX 16 series card, the GitHub builds for Windows and Linux can download an optional CUDA pack through the settings.

That download is an option for compatible NVIDIA hardware. You do not need it for AMD, Intel or CPU processing.

## When the GPU cannot do the job

If WhisPaste finds no compatible GPU, it uses the processor. You can also force this route with the “CPU only” setting.

If loading a model hangs on the GPU, WhisPaste retries once using a CPU-only engine. After two consecutive loading crashes, acceleration is disabled until you turn it back on in the settings.

Start by checking your operating system, RAM and graphics driver. The [GPU compatibility checker](/en/gpu-compatibility/) helps you understand your setup and runs entirely in your browser without sending your selections anywhere.

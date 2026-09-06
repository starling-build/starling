// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// Video player app — runs as a child process of DesktopShellApp.
// Uses GpuDmaBufRenderer (via runApp) for GPU-accelerated rendering.
// Decodes video with a spawned ffmpeg (see PipeDecoder — no libav is
// linked), frames uploaded as external textures.

// No default file: without VIDEO_PATH the player starts empty and the user
// picks a file through the shared open dialog.
let videoPath = ProcessInfo.processInfo.environment["VIDEO_PATH"] ?? ""

runApp(
    StarlingApp(
        title: "Video Player",
        home: ColoredBox(
            color: Color(0xFF000000),
            child: VideoPlayerWidget(path: videoPath)
        )
    )
)

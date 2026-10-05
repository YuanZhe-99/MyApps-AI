package com.yuanzhe.myapps_ai

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Engine-scoped registration; model clients are created only on explicit calls. */
class MyAppsAiPlatformPlugin : FlutterPlugin {
    private var bridge: GenAiChannel? = null

    /** Purpose: Register bridge. Inputs: binding. Returns: None. Side effects: Installs channel. Notes: No inference. */
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge = GenAiChannel(binding.applicationContext).also {
            it.attach(binding.binaryMessenger)
        }
    }

    /** Purpose: Release bridge. Inputs: binding. Returns: None. Side effects: Cancels and closes clients. Notes: Engine lifetime. */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        bridge?.detach()
        bridge = null
    }
}

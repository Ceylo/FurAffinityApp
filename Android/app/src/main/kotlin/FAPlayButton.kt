//
//  FAPlayButton.kt
//  FurAffinity (Android)
//
//  Material 3 1.4 has no expressive toggle button, so the Android 17 pill-to-rect
//  morph is a sprung corner radius. Shown from Swift through ComposeView.
//

package fur.affinity.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import skip.ui.ComposeContext
import skip.ui.ContentComposer

class FAPlayButton(private val bridge: FAAudioBridge, private val isPlaying: Boolean) : ContentComposer {
    @Composable
    override fun Compose(context: ComposeContext) {
        var playing by remember { mutableStateOf(isPlaying) }
        LaunchedEffect(isPlaying) { playing = isPlaying }
        val interactionSource = remember { MutableInteractionSource() }
        val pressed by interactionSource.collectIsPressedAsState()
        val corner by animateDpAsState(
            targetValue = when {
                pressed -> 12.dp
                playing -> 18.dp
                else -> 28.dp
            },
            animationSpec = spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium),
            label = "playButtonCorner",
        )
        FilledIconButton(
            onClick = {
                playing = !playing
                if (playing) bridge.play() else bridge.pause()
            },
            modifier = context.modifier.size(width = 72.dp, height = 56.dp),
            shape = RoundedCornerShape(corner),
            interactionSource = interactionSource,
        ) {
            Icon(
                imageVector = if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = if (playing) "Pause" else "Play",
                modifier = Modifier.size(32.dp),
            )
        }
    }
}

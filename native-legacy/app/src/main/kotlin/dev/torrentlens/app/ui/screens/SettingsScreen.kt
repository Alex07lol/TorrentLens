package dev.torrentlens.app.ui.screens

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.ui.Format
import dev.torrentlens.core.data.settings.AppSettings
import dev.torrentlens.core.domain.model.ReadingDirection
import dev.torrentlens.core.domain.model.ReadingMode

@Composable
fun SettingsScreen(
    settings: AppSettings,
    downloadDir: String?,
    onThemeChange: (Boolean?) -> Unit,
    onDownloadLimit: (Long) -> Unit,
    onUploadLimit: (Long) -> Unit,
    onWifiOnly: (Boolean) -> Unit,
    onSeedAfterComplete: (Boolean) -> Unit,
    onReadingDefaults: (ReadingMode, ReadingDirection) -> Unit,
    onChooseFolder: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var downloadLimitText by remember(settings.globalDownloadLimitBytesPerSec) {
        mutableStateOf(settings.globalDownloadLimitBytesPerSec.toString())
    }
    var uploadLimitText by remember(settings.globalUploadLimitBytesPerSec) {
        mutableStateOf(settings.globalUploadLimitBytesPerSec.toString())
    }

    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { }

    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SectionTitle("Appearance")
        Card {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Dark theme")
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedButton(onClick = { onThemeChange(null) }, enabled = settings.themeDark != null) {
                            Text("System")
                        }
                        OutlinedButton(onClick = { onThemeChange(true) }, enabled = settings.themeDark != true) {
                            Text("Dark")
                        }
                        OutlinedButton(onClick = { onThemeChange(false) }, enabled = settings.themeDark != false) {
                            Text("Light")
                        }
                    }
                }
            }
        }

        SectionTitle("Storage")
        Card {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Download folder")
                Text(
                    downloadDir ?: "App storage (no permission required)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedButton(onClick = onChooseFolder) { Text("Choose folder") }
                Text(
                    "TorrentLens downloads through the Storage Access Framework and never asks for " +
                        "unrestricted storage access.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        SectionTitle("Bandwidth")
        Card {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = downloadLimitText,
                    onValueChange = { downloadLimitText = it.filter(Char::isDigit) },
                    label = { Text("Download limit (bytes/s, 0 = unlimited)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = uploadLimitText,
                    onValueChange = { uploadLimitText = it.filter(Char::isDigit) },
                    label = { Text("Upload limit (bytes/s, 0 = unlimited)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(onClick = {
                    onDownloadLimit(downloadLimitText.toLongOrNull() ?: 0)
                    onUploadLimit(uploadLimitText.toLongOrNull() ?: 0)
                }) { Text("Apply limits") }
                Text(
                    "Current: ↓ ${Format.rate(settings.globalDownloadLimitBytesPerSec)}, " +
                        "↑ ${Format.rate(settings.globalUploadLimitBytesPerSec)}",
                    style = MaterialTheme.typography.bodySmall,
                )
                HorizontalDivider()
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Wi-Fi only downloads")
                    Switch(checked = settings.wifiOnlyDownloads, onCheckedChange = onWifiOnly)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Seed after completing")
                    Switch(checked = settings.seedAfterComplete, onCheckedChange = onSeedAfterComplete)
                }
            }
        }

        SectionTitle("Reading")
        Card {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Page-by-page")
                    Switch(
                        checked = settings.defaultReadingMode == ReadingMode.PAGED,
                        onCheckedChange = { paged ->
                            onReadingDefaults(
                                if (paged) ReadingMode.PAGED else ReadingMode.VERTICAL_SCROLL,
                                settings.defaultReadingDirection,
                            )
                        },
                    )
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Right-to-left (manga)")
                    Switch(
                        checked = settings.defaultReadingDirection == ReadingDirection.RIGHT_TO_LEFT,
                        onCheckedChange = { rtl ->
                            onReadingDefaults(
                                settings.defaultReadingMode,
                                if (rtl) ReadingDirection.RIGHT_TO_LEFT else ReadingDirection.LEFT_TO_RIGHT,
                            )
                        },
                    )
                }
            }
        }

        SectionTitle("Notifications")
        Card {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Download progress notifications")
                Text(
                    "Used to show the persistent progress notification while a user-initiated transfer runs.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    OutlinedButton(onClick = { notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) }) {
                        Text("Grant notification permission")
                    }
                }
                Text(
                    "Battery optimisation is not requested. If downloads stop in the background, " +
                        "your device's battery settings are the usual cause — TorrentLens cannot override them.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall)
}

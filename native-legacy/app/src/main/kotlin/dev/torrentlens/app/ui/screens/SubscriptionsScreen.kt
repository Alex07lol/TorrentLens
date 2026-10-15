package dev.torrentlens.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.torrentlens.app.ui.Format
import dev.torrentlens.app.ui.components.EmptyState
import dev.torrentlens.core.domain.model.GitHubSubscription

/**
 * GitHub subscriptions: follow a repository, check for a newer published
 * version, and see the verification outcome for each release.
 */
@Composable
fun SubscriptionsScreen(
    subscriptions: List<GitHubSubscription>,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit,
    onCheck: (String) -> Unit,
    onCheckAll: () -> Unit,
    isBusy: Boolean,
    modifier: Modifier = Modifier,
) {
    var input by remember { mutableStateOf("") }

    Column(modifier = modifier.fillMaxSize()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                label = { Text("owner/repo or a GitHub URL") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { onAdd(input.trim()); input = "" },
                    enabled = input.isNotBlank() && !isBusy,
                    modifier = Modifier.weight(1f),
                ) { Text("Follow") }
                OutlinedButton(onClick = onCheckAll, enabled = !isBusy && subscriptions.isNotEmpty()) {
                    Text("Check all")
                }
            }
            Text(
                "A repository is only treated as an app source when it publishes an explicit " +
                    "manifest file (torrentlens-manifest.json, update-manifest.json or *.manifest.json). " +
                    "Signed manifests are verified with Ed25519; unsigned ones are labelled as such and " +
                    "are never installed automatically.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (subscriptions.isEmpty()) {
                item {
                    EmptyState(
                        title = "No subscriptions",
                        message = "Follow a GitHub repository to be told when it publishes a new version.",
                    )
                }
            } else {
                items(subscriptions, key = { it.id }) { subscription ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(subscription.displayName, style = MaterialTheme.typography.titleSmall)
                            Text(
                                buildString {
                                    append(if (subscription.includePrereleases) "Prereleases on" else "Releases only")
                                    subscription.installedVersion?.let { append(" • installed $it") }
                                    subscription.lastCheckedAtEpochMillis?.let {
                                        append(" • checked ${Format.relativeAge(it)}")
                                    }
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            subscription.lastError?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                TextButton(onClick = { onCheck(subscription.id) }, enabled = !isBusy) { Text("Check now") }
                                TextButton(onClick = { onRemove(subscription.id) }) { Text("Unfollow") }
                            }
                        }
                    }
                }
            }
        }
    }
}

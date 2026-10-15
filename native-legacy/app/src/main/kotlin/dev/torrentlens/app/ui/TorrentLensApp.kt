package dev.torrentlens.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dev.torrentlens.app.service.TorrentDownloadService
import dev.torrentlens.app.ui.import.ImportSheet
import dev.torrentlens.app.ui.reader.ReaderScreen
import dev.torrentlens.app.ui.screens.DashboardScreen
import dev.torrentlens.app.ui.screens.DownloadsScreen
import dev.torrentlens.app.ui.screens.LibraryScreen
import dev.torrentlens.app.ui.screens.SettingsScreen
import dev.torrentlens.app.ui.screens.SubscriptionsScreen
import java.io.File

private enum class Destination(val route: String, val label: String, val icon: ImageVector) {
    DASHBOARD("dashboard", "Dashboard", Icons.Filled.Home),
    DOWNLOADS("downloads", "Downloads", Icons.Filled.Download),
    LIBRARY("library", "Library", Icons.Filled.Book),
    SUBSCRIPTIONS("subscriptions", "GitHub", Icons.Filled.RssFeed),
    SETTINGS("settings", "Settings", Icons.Filled.Settings),
}

private const val READER_ROUTE = "reader/{itemId}"

/**
 * The Android shell: bottom navigation, a dashboard-first home, and a single
 * import sheet reachable from anywhere. This is intentionally a phone layout —
 * not a desktop layout compressed onto a small screen.
 */
@Composable
fun TorrentLensApp(
    viewModel: TorrentLensViewModel,
    cacheRoot: File,
    initialImportText: String?,
) {
    val navController = rememberNavController()
    val context = LocalContext.current

    val tasks by viewModel.tasks.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val subscriptions by viewModel.subscriptionsList.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val engineStatus by viewModel.engineStatus.collectAsStateWithLifecycle()
    val files by viewModel.taskFiles.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()

    var showImport by remember { mutableStateOf(false) }
    var pendingImport by remember { mutableStateOf<String?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(initialImportText) {
        if (!initialImportText.isNullOrBlank()) {
            pendingImport = initialImportText
            showImport = true
        }
    }

    LaunchedEffect(message) {
        message?.let {
            snackbarHostState.showSnackbar(it.text)
            viewModel.clearMessage()
        }
    }

    // The foreground service exists only while something is actually transferring.
    LaunchedEffect(tasks) {
        if (tasks.any { it.stats.state.isActive }) {
            TorrentDownloadService.start(context)
        }
    }

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            viewModel.setDefaultDownloadDir(uri.toString())
            viewModel.clearMessage()
        }
    }

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            if (currentRoute != READER_ROUTE) {
                FloatingActionButton(onClick = { pendingImport = null; showImport = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "Add a torrent")
                }
            }
        },
        bottomBar = {
            if (currentRoute != READER_ROUTE) {
                NavigationBar {
                    Destination.entries.forEach { destination ->
                        NavigationBarItem(
                            selected = currentRoute == destination.route,
                            onClick = {
                                navController.navigate(destination.route) {
                                    popUpTo(Destination.DASHBOARD.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(destination.icon, contentDescription = destination.label) },
                            label = { Text(destination.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Destination.DASHBOARD.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(Destination.DASHBOARD.route) {
                DashboardScreen(
                    tasks = tasks,
                    library = library,
                    settings = settings,
                    engineStatus = engineStatus,
                )
            }

            composable(Destination.DOWNLOADS.route) {
                DownloadsScreen(
                    tasks = tasks,
                    selectedTask = tasks.firstOrNull { it.id == pendingImport },
                    files = files,
                    onPause = viewModel::pauseTask,
                    onResume = viewModel::resumeTask,
                    onRemove = { viewModel.removeTask(it, deleteFiles = false) },
                    onOpenFiles = { id -> viewModel.openFileSelection(id) },
                    onToggleFile = { taskId, path, selected -> viewModel.setFileSelected(taskId, path, selected) },
                    onApplySelection = { taskId -> viewModel.applyFileSelection(taskId) },
                )
            }

            composable(Destination.LIBRARY.route) {
                LibraryScreen(
                    items = library,
                    onAdd = { viewModel.addToLibrary(it) },
                    onOpen = { item -> navController.navigate("reader/${item.id}") },
                    onRemove = { viewModel.removeFromLibrary(it) },
                )
            }

            composable(Destination.SUBSCRIPTIONS.route) {
                SubscriptionsScreen(
                    subscriptions = subscriptions,
                    onAdd = viewModel::addSubscription,
                    onRemove = viewModel::removeSubscription,
                    onCheck = viewModel::checkSubscription,
                    onCheckAll = viewModel::checkAllSubscriptions,
                    isBusy = busy,
                )
            }

            composable(Destination.SETTINGS.route) {
                SettingsScreen(
                    settings = settings,
                    downloadDir = settings.defaultDownloadDirUri,
                    onThemeChange = viewModel::setThemeDark,
                    onDownloadLimit = viewModel::setDownloadLimit,
                    onUploadLimit = viewModel::setUploadLimit,
                    onWifiOnly = viewModel::setWifiOnly,
                    onSeedAfterComplete = viewModel::setSeedAfterComplete,
                    onReadingDefaults = viewModel::setDefaultReading,
                    onChooseFolder = { folderPicker.launch(null) },
                )
            }

            composable(
                route = READER_ROUTE,
                arguments = listOf(navArgument("itemId") { type = NavType.StringType }),
            ) { entry ->
                val itemId = entry.arguments?.getString("itemId")
                val item = library.firstOrNull { it.id == itemId }
                if (item == null) {
                    Text("That document is no longer in the library.")
                } else {
                    ReaderScreen(
                        item = item,
                        cacheRoot = cacheRoot,
                        defaultMode = settings.defaultReadingMode,
                        defaultDirection = settings.defaultReadingDirection,
                        onBack = { navController.popBackStack() },
                        onSaveProgress = { locator, percent, mode, direction ->
                            viewModel.saveReadingProgress(item.id, locator, percent, mode, direction)
                        },
                        onAddBookmark = { locator -> viewModel.addBookmark(item.id, locator, item.title) },
                    )
                }
            }
        }
    }

    if (showImport) {
        ImportSheet(
            initialText = pendingImport,
            onDismiss = { showImport = false; pendingImport = null },
            onImportText = { viewModel.importTorrent(it) },
            onPickedTorrent = { _, location -> viewModel.importTorrent(location) },
            onFolderChosen = { viewModel.setDefaultDownloadDir(it) },
            currentFolder = settings.defaultDownloadDirUri,
            isBusy = busy,
        )
    }
}

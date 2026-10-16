@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.rivendell.stayword.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.AudioFile
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.rivendell.stayword.R
import com.rivendell.stayword.domain.RecordingFolder
import com.rivendell.stayword.processing.ModelInstallState
import com.rivendell.stayword.ui.components.NameDialog

@Composable
fun LibraryScreen(
    folders: List<RecordingFolder>,
    modelState: ModelInstallState,
    onAll: () -> Unit,
    onFavorites: () -> Unit,
    onDeleted: () -> Unit,
    onFolder: (RecordingFolder) -> Unit,
    onCreateFolder: (String) -> Unit,
    onRenameFolder: (String, String) -> Unit,
    onDeleteFolder: (String) -> Unit,
    onReorderFolders: (List<String>) -> Unit,
    onRecord: () -> Unit,
) {
    var showCreate by remember { mutableStateOf(false) }
    var renameFolder by remember { mutableStateOf<RecordingFolder?>(null) }
    var deleteFolder by remember { mutableStateOf<RecordingFolder?>(null) }

    Scaffold(
        topBar = {
            LargeTopAppBar(
                title = { Text(stringResource(R.string.library)) },
                actions = {
                    IconButton(onClick = { showCreate = true }) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.new_folder))
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = onRecord,
                icon = { Icon(Icons.Default.Mic, contentDescription = null) },
                text = { Text(stringResource(R.string.record)) },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 104.dp),
        ) {
            when (modelState) {
                is ModelInstallState.Installing -> item {
                    ModelSetupBanner(stringResource(R.string.model_setup))
                }
                is ModelInstallState.Failed -> item {
                    ModelSetupBanner(stringResource(R.string.model_setup_failed), error = true)
                }
                else -> Unit
            }

            item {
                LibraryDestination(
                    title = stringResource(R.string.all_recordings),
                    icon = { Icon(Icons.Default.AudioFile, contentDescription = null) },
                    onClick = onAll,
                )
            }
            item {
                LibraryDestination(
                    title = stringResource(R.string.favorites),
                    icon = { Icon(Icons.Default.FavoriteBorder, contentDescription = null) },
                    onClick = onFavorites,
                )
            }
            item {
                LibraryDestination(
                    title = stringResource(R.string.recently_deleted),
                    icon = { Icon(Icons.Default.DeleteOutline, contentDescription = null) },
                    onClick = onDeleted,
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                Text(
                    stringResource(R.string.folders),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                )
            }
            if (folders.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.no_folders_yet),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
                    )
                }
            }
            itemsIndexed(folders, key = { _, folder -> folder.id }) { index, folder ->
                FolderRow(
                    folder = folder,
                    canMoveUp = index > 0,
                    canMoveDown = index < folders.lastIndex,
                    onClick = { onFolder(folder) },
                    onRename = { renameFolder = folder },
                    onDelete = { deleteFolder = folder },
                    onMoveUp = {
                        val ids = folders.map { it.id }.toMutableList()
                        ids[index] = ids[index - 1].also { ids[index - 1] = ids[index] }
                        onReorderFolders(ids)
                    },
                    onMoveDown = {
                        val ids = folders.map { it.id }.toMutableList()
                        ids[index] = ids[index + 1].also { ids[index + 1] = ids[index] }
                        onReorderFolders(ids)
                    },
                )
            }
        }
    }

    if (showCreate) {
        NameDialog(
            title = stringResource(R.string.new_folder),
            label = stringResource(R.string.folder_name),
            onDismiss = { showCreate = false },
            onConfirm = { name -> showCreate = false; onCreateFolder(name) },
        )
    }
    renameFolder?.let { folder ->
        NameDialog(
            title = stringResource(R.string.rename_folder),
            label = stringResource(R.string.folder_name),
            initialValue = folder.name,
            onDismiss = { renameFolder = null },
            onConfirm = { name -> renameFolder = null; onRenameFolder(folder.id, name) },
        )
    }
    deleteFolder?.let { folder ->
        AlertDialog(
            onDismissRequest = { deleteFolder = null },
            title = { Text(stringResource(R.string.delete_folder)) },
            text = { Text(stringResource(R.string.folder_delete_body)) },
            confirmButton = {
                TextButton(onClick = { deleteFolder = null; onDeleteFolder(folder.id) }) {
                    Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteFolder = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }
}

@Composable
private fun LibraryDestination(
    title: String,
    icon: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = icon,
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

@Composable
private fun FolderRow(
    folder: RecordingFolder,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onClick: () -> Unit,
    onRename: () -> Unit,
    onDelete: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(folder.name) },
        leadingContent = { Icon(Icons.Default.Folder, contentDescription = null) },
        trailingContent = {
            Box {
                IconButton(onClick = { menuExpanded = true }) {
                    Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.more_options))
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.rename)) },
                        onClick = { menuExpanded = false; onRename() },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.move_up)) },
                        leadingIcon = { Icon(Icons.Default.ArrowUpward, contentDescription = null) },
                        enabled = canMoveUp,
                        onClick = { menuExpanded = false; onMoveUp() },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.move_down)) },
                        leadingIcon = { Icon(Icons.Default.ArrowDownward, contentDescription = null) },
                        enabled = canMoveDown,
                        onClick = { menuExpanded = false; onMoveDown() },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) },
                        onClick = { menuExpanded = false; onDelete() },
                    )
                }
            }
        },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

@Composable
private fun ModelSetupBanner(text: String, error: Boolean = false) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Text(
            text,
            color = if (error) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSecondaryContainer,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

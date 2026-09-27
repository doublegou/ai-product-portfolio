package com.rivendell.stayword.data

import android.content.Context
import androidx.room3.Database
import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.sqlite.driver.AndroidSQLiteDriver
import kotlinx.coroutines.Dispatchers

@Database(
    entities = [
        FolderEntity::class,
        RecordingEntity::class,
        TranscriptSegmentEntity::class,
        RecordingMarkerEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class StayWordDatabase : RoomDatabase() {
    abstract fun dao(): StayWordDao

    companion object {
        fun create(context: Context): StayWordDatabase =
            Room.databaseBuilder<StayWordDatabase>(
                context = context.applicationContext,
                name = "stayword.db",
            )
                .setDriver(AndroidSQLiteDriver())
                .setQueryCoroutineContext(Dispatchers.IO)
                .build()
    }
}

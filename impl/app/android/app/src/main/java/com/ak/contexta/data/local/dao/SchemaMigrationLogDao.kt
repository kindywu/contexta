package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import com.ak.contexta.data.local.entity.SchemaMigrationLogEntity

@Dao
interface SchemaMigrationLogDao {
    @Query("SELECT * FROM schema_migration_log ORDER BY id DESC LIMIT 1")
    suspend fun getLatest(): SchemaMigrationLogEntity?

    @Insert
    suspend fun insert(log: SchemaMigrationLogEntity)

    @Query("SELECT to_version FROM schema_migration_log ORDER BY id DESC LIMIT 1")
    suspend fun getCurrentVersion(): Int?
}

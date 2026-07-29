package com.ak.contexta.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ak.contexta.data.local.entity.ArticleParagraphEntity

@Dao
interface ArticleParagraphDao {
    @Query("SELECT * FROM article_paragraph WHERE article_id = :articleId ORDER BY order_index ASC")
    suspend fun getByArticle(articleId: Long): List<ArticleParagraphEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(paragraphs: List<ArticleParagraphEntity>)

    @Query("DELETE FROM article_paragraph WHERE article_id = :articleId")
    suspend fun deleteByArticle(articleId: Long)
}

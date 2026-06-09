class AddFullTextSearchToPosts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE posts
        ADD COLUMN search_vector tsvector
          GENERATED ALWAYS AS (
            to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))
          ) STORED
    SQL

    add_index :posts, :search_vector, using: :gin, name: "index_posts_on_search_vector"
  end

  def down
    remove_index :posts, name: "index_posts_on_search_vector"
    remove_column :posts, :search_vector
  end
end

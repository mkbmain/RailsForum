class MakeReactionsPolymorphic < ActiveRecord::Migration[8.1]
  def change
    # Remove FK and old indexes before touching the column
    remove_foreign_key :reactions, :posts
    remove_index :reactions, name: :index_reactions_on_post_id
    remove_index :reactions, name: :index_reactions_on_user_id_and_post_id

    # Rename post_id to reactionable_id and add the type column
    rename_column :reactions, :post_id, :reactionable_id
    add_column    :reactions, :reactionable_type, :string

    # Backfill all existing rows as Post reactions
    reversible do |dir|
      dir.up { execute "UPDATE reactions SET reactionable_type = 'Post'" }
    end

    # Enforce not-null now that every row has a type
    change_column_null :reactions, :reactionable_type, false

    # Polymorphic indexes
    add_index :reactions, [ :reactionable_type, :reactionable_id ],
              name: :index_reactions_on_reactionable
    add_index :reactions, [ :user_id, :reactionable_type, :reactionable_id ],
              unique: true, name: :index_reactions_on_user_and_reactionable
  end
end

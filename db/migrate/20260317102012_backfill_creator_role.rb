class BackfillCreatorRole < ActiveRecord::Migration[8.1]
  def up
    result = execute("SELECT id FROM roles WHERE name = 'creator'")
    creator_id = result.first&.fetch("id")
    return unless creator_id  # seeds haven't run yet (e.g. fresh CI); safe to skip

    execute(<<~SQL)
      INSERT INTO user_roles (user_id, role_id)
      SELECT u.id, #{creator_id}
      FROM users u
      LEFT JOIN user_roles ur ON ur.user_id = u.id
      WHERE ur.id IS NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

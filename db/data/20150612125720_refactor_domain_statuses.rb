class RefactorDomainStatuses < ActiveRecord::Migration
  def self.up
    Domain.find_each do |x|
      statuses = []
      x.domain_statuses.each do |ds|
        statuses << ds.value
      end
      x.update_column('statuses', statuses)
    end
  end

  def self.down
    raise ActiveRecord::IrreversibleMigration
  end
end

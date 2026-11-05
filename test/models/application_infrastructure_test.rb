require "test_helper"

class ApplicationInfrastructureTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "application jobs, mailers, and OAuth models inherit their Rails base classes" do
    assert_equal ActiveJob::Base, ApplicationJob.superclass
    assert_equal ActionMailer::Base, ApplicationMailer.superclass
    assert_equal ApplicationRecord, OauthApplication.superclass
    assert_equal ApplicationRecord, OauthAccessGrant.superclass
    assert_equal ApplicationRecord, OauthAccessToken.superclass
  end
end

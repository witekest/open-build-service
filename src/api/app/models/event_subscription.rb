class EventSubscription < ApplicationRecord
  RECEIVER_ROLE_TEXTS = {
    maintainer: 'Maintainer',
    bugowner: 'Bugowner',
    reader: 'Reader',
    source_maintainer: 'Maintainer of the source',
    target_maintainer: 'Maintainer of the target',
    reviewer: 'Reviewer',
    commenter: 'Commenter',
    creator: 'Creator',
    watcher: 'Watching the project',
    source_watcher: 'Watching the source project',
    target_watcher: 'Watching the target project',
    any_role: 'Any role'
  }.freeze
  BETA_RECEIVER_ROLE_TEXTS = {
    package_watcher: 'Watching the package',
    source_package_watcher: 'Watching the source package',
    target_package_watcher: 'Watching the target package',
    request_watcher: 'Watching the request'
  }.freeze

  enum channel: {
    disabled: 0,
    instant_email: 1,
    web: 2,
    rss: 3,
    scm: 4
  }

  # Channels used by the event system, but not meant to be enabled by hand
  INTERNAL_ONLY_CHANNELS = ['scm'].freeze

  serialize :payload, JSON

  belongs_to :user, inverse_of: :event_subscriptions, optional: true
  belongs_to :group, inverse_of: :event_subscriptions, optional: true
  belongs_to :token, inverse_of: :event_subscriptions, optional: true
  belongs_to :package, optional: true
  belongs_to :workflow_run, optional: true

  validates :receiver_role, inclusion: {
    in: [:maintainer, :bugowner, :reader, :source_maintainer, :target_maintainer,
         :reviewer, :commenter, :creator, :watcher, :source_watcher, :target_watcher,
         :package_watcher, :target_package_watcher, :source_package_watcher, :request_watcher, :any_role]
  }

  scope :for_eventtype, ->(eventtype) { where(eventtype: eventtype) }
  scope :defaults, -> { where(user_id: nil, group_id: nil) }
  scope :for_subscriber, lambda { |subscriber|
    case subscriber
    when User
      where(user: subscriber)
    when Group
      where(group: subscriber)
    else
      defaults
    end
  }

  after_save :track_event_subscription_saved

  def self.receiver_roles_to_display(user)
    roles = RECEIVER_ROLE_TEXTS.keys
    # We have to show the new_watchlist subscription options to the admin in order to allow the global
    # configuration
    roles += BETA_RECEIVER_ROLE_TEXTS.keys if Flipper.enabled?(:new_watchlist, user) || User.possibly_nobody.is_admin?
    roles
  end

  def subscriber
    if user_id.present?
      user
    elsif group_id.present?
      group
    end
  end

  def subscriber=(subscriber)
    case subscriber
    when User
      self.user = subscriber
    when Group
      self.group = subscriber
    end
  end

  def event_class
    # NOTE: safe_ is required here because for some reason we were getting an uninitialized constant error
    # from this line from the functional tests (though not in rspec or in rails server)
    eventtype.safe_constantize
  end

  def receiver_role
    self[:receiver_role].to_sym
  end

  def parameters_for_notification
    { subscriber: subscriber,
      subscription_receiver_role: receiver_role }
  end

  def self.without_disabled_or_internal_channels
    channels.keys.reject { |channel| channel == 'disabled' || channel.in?(INTERNAL_ONLY_CHANNELS) }
  end

  def track_event_subscription_saved
    RabbitmqBus.send_to_bus('metrics',
                            "event_subscription.event,event_type=#{eventtype},receiver_role=#{receiver_role},enabled=#{enabled},user=#{user},channel=#{channel} value=1")
  end
end

# == Schema Information
#
# Table name: event_subscriptions
#
#  id              :integer          not null, primary key
#  channel         :integer          default("disabled"), not null
#  enabled         :boolean          default(FALSE)
#  eventtype       :string(255)      not null
#  payload         :text(65535)
#  receiver_role   :string(255)      not null
#  created_at      :datetime
#  updated_at      :datetime
#  group_id        :integer          indexed
#  package_id      :integer          indexed
#  token_id        :integer          indexed
#  user_id         :integer          indexed
#  workflow_run_id :integer          indexed
#
# Indexes
#
#  index_event_subscriptions_on_group_id         (group_id)
#  index_event_subscriptions_on_package_id       (package_id)
#  index_event_subscriptions_on_token_id         (token_id)
#  index_event_subscriptions_on_user_id          (user_id)
#  index_event_subscriptions_on_workflow_run_id  (workflow_run_id)
#

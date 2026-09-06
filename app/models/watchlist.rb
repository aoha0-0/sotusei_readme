# frozen_string_literal: true

class Watchlist < ApplicationRecord
  include WatchlistNotifiable
  include WatchlistSchedulable
  attr_accessor :tag_names

  belongs_to :user

  has_many :notification_deliveries, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :watchlist_tags, dependent: :destroy
  has_many :tags, through: :watchlist_tags

  before_validation :set_end_at_to_end_of_day, if: :end_at_time_blank?

  validates :title, presence: true, length: { maximum: 255 }
  validate :start_at_or_end_at_must_be_present

  VALID_URL_REGEX = %r{\Ahttps?://\S+\z}
  validates :url, allow_blank: true, format: { with: VALID_URL_REGEX }

  validate :end_at_must_be_future, on: :create
  validate :end_at_must_be_after_start_at

  validates :reception_detail, length: { maximum: 20 }, allow_blank: true

  enum :reception_type, {
    not_set: 0,     # 指定なし
    lottery: 1,     # 抽選受付
    first_come: 2,  # 先着受付
    made_to_order: 3 # 受注販売
  }, default: :not_set

  def reception_type_label
    I18n.t(
      "enums.watchlist.reception_type.#{reception_type}"
    )
  end

  def reception_label_text
    if reception_detail.present? && reception_type != 'not_set'
      "【#{reception_detail}#{reception_type_label}】"
    elsif reception_detail.present?
      "【#{reception_detail}】"
    elsif reception_type != 'not_set'
      "【#{reception_type_label}】"
    end
  end

  def display_title
    "#{reception_label_text}#{title}"
  end

  def save_tags
    names = tag_names
            .to_s
            .split(/[,，、]/)
            .map(&:strip)
            .reject(&:blank?)

    selected_tags = names.map do |name|
      user.tags.find_or_create_by!(name: name)
    end

    self.tags = selected_tags
  end

  # 「これからの予定」を取得するスコープ
  scope :upcoming, lambda {
    target_date_sql = <<~SQL
      CASE#{' '}
        WHEN start_at < '#{Time.current.to_fs(:db)}' THEN COALESCE(end_at, start_at)
        ELSE LEAST(start_at, COALESCE(end_at, start_at))
      END ASC
    SQL

    where(is_done: false)
      .where('end_at >= ? OR end_at IS NULL', Time.current)
      .order(Arel.sql(target_date_sql))
  }

  # 「これまでの足跡」を取得するスコープ
  scope :past, lambda {
    where(is_done: true)
      .or(where('end_at < ?', Time.current))
      .order(end_at: :desc)
  }

  scope :tagged_with, lambda { |keyword|
    where(
      id: WatchlistTag
          .joins(:tag)
          .where('tags.name ILIKE ?', "%#{keyword}%")
          .select(:watchlist_id)
    )
  }

  private

  def end_at_time_blank?
    # パターンA: 開始日時があって、締切が完全に空のとき
    return true if start_at.present? && end_at.blank?

    # パターンB: 締切があって、時間が 00:00:00（日付のみ入力）のとき
    true if end_at.present? && end_at == end_at.beginning_of_day
  end

  def set_end_at_to_end_of_day
    if end_at.blank? && start_at.present?
      # 締切が空なら、開始日時の日の 23:59:59 をセット
      self.end_at = start_at.end_of_day
    elsif end_at.present?
      # 締切が入力されているなら、その締切日の 23:59:59 に上書き
      self.end_at = end_at.end_of_day
    end
  end

  # 開始時間または締切時間のどちらかは必須
  def start_at_or_end_at_must_be_present
    return unless start_at.blank? && end_at.blank?

    errors.add(:base, :start_at_or_end_at_blank)
  end

  def end_at_must_be_after_start_at
    return unless start_at.present? && end_at.present? && end_at <= start_at

    errors.add(:end_at, :must_be_after_start_at)
  end

  def end_at_must_be_future
    return unless end_at.present? && end_at < Time.current

    errors.add(:end_at, :must_be_future)
  end
end

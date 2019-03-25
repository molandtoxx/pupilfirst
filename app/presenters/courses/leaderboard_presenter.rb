module Courses
  class LeaderboardPresenter < ApplicationPresenter
    class Student < SimpleDelegator
      attr_reader :score, :rank
      attr_accessor :delta

      def initialize(founder, score, rank, current_founder)
        @score = score
        @rank = rank
        @current_founder = current_founder

        super(founder)
      end

      def level_number
        @level_number ||= level.number
      end

      def current_student?
        @current_student ||= (id == @current_founder&.id)
      end
    end

    def initialize(view_context, course, page: nil)
      @course ||= course
      @page = page

      super(view_context)
    end

    def school_name
      @school_name ||= begin
        raise 'current_school cannot be missing here' if current_school.blank?

        current_school.name
      end
    end

    def start_date
      lts.week_start.strftime('%B %-d')
    end

    def end_date
      lts.week_end.strftime('%B %-d')
    end

    def toppers
      @toppers ||= students.find_all { |e| e.rank == 1 }
    end

    def heading
      if current_founder_is_topper?
        return '<strong>You</strong> are at the top of the leaderboard. <strong>Congratulations!</strong>'.html_safe
      end

      multiple_mid_text = 'are at the top of the leaderboard this week, sharing a score of '

      h = if toppers.count == 1
        "<strong>#{toppers.first.name}</strong> is at the top of the leaderboard this week with a score of "
      elsif toppers.count < 4
        names = toppers.map { |s| "<strong>#{s.name}</strong>" }
        "#{names.to_sentence} #{multiple_mid_text}"
      else
        others_count = toppers.count - 2
        names = toppers[0..1].map { |s| "<strong>#{s.name}</strong>" }
        "#{names.join(', ')} and <strong>#{others_count} others</strong> #{multiple_mid_text}"
      end

      (h + "<strong>#{top_score}</strong>.").html_safe
    end

    def students
      @students ||= begin
        current_leaderboard.map do |student_id, student|
          delta = if last_leaderboard[student_id].present?
            last_leaderboard[student_id].rank - student.rank
          end

          student.delta = delta
          student
        end
      end
    end

    def inactive_students_count
      @inactive_students_count ||= founders.count - students.count
    end

    def previous_page?
      page < 8
    end

    def next_page?
      page.positive?
    end

    def previous_page_link
      view.leaderboard_course_path(page: page + 1)
      "?page=#{page + 1}"
    end

    def next_page_link
      if page == 1
        view.leaderboard_course_path
      else
        view.leaderboard_course_path(page: page - 1)
      end
    end

    def course_entries(from, to)
      LeaderboardEntry.where(founder: founders, period_from: from, period_to: to)
    end

    def rank_change_icon(delta)
      if delta >= 10
        view.image_tag('courses/leaderboard/rank-change-up-double.svg', class: 'img-fluid', alt: 'Rank change up double')
      elsif delta.positive?
        view.image_tag('courses/leaderboard/rank-change-up.svg', class: 'img-fluid', alt: 'Rank change up')
      elsif delta.zero?
        view.image_tag('courses/leaderboard/rank-no-change.svg', class: 'img-fluid', alt: 'Rank no change')
      elsif delta > -10
        view.image_tag('courses/leaderboard/rank-change-down.svg', class: 'img-fluid', alt: 'Rank change down')
      else
        view.image_tag('courses/leaderboard/rank-change-down-double.svg', class: 'img-fluid', alt: 'Rank change down double')
      end
    end

    def format_delta(delta)
      return if delta.blank?

      delta.negative? ? delta * -1 : delta
    end

    private

    def top_score
      @top_score ||= toppers.first.score
    end

    def current_founder_is_topper?
      current_founder.present? && current_founder.id.in?(toppers.map(&:id))
    end

    def page
      @page ||= begin
        parsed_page = view.params[:page].to_i
        parsed_page.between?(0, 12) ? parsed_page : 0
      end
    end

    def lts
      @lts ||= LeaderboardTimeService.new(page)
    end

    def founders
      @course.founders.not_exited.where(excluded_from_leaderboard: false)
    end

    def current_leaderboard
      @current_leaderboard ||= ranked_students(lts.week_start, lts.week_end)
    end

    def last_leaderboard
      @last_leaderboard ||= ranked_students(lts.last_week_start, lts.last_week_end)
    end

    def ranked_students(from, to)
      last_rank = 0
      last_score = BigDecimal::INFINITY

      course_entries(from, to).order(score: :DESC).each_with_object({}).with_index(1) do |(entry, students), index|
        rank = entry.score < last_score ? index : last_rank

        students[entry.founder.id] = Student.new(entry.founder, entry.score, rank, current_founder)

        last_rank = rank
        last_score = entry.score
      end
    end
  end
end

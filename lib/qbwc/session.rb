class QBWC::Session

  attr_reader :user, :company, :ticket, :progress
  attr_accessor :error, :status_code, :status_severity

  @@session = nil

	def self.get(ticket)
		@@session
	end

  def initialize(user = nil, company = nil, ticket = nil)
    @user = user
    @company = company
    @current_job = nil
    @error = nil
    @progress = 0
    @iterator_id = nil
    @initial_job_count = pending_jobs.length

    @ticket = ticket || Digest::SHA1.hexdigest("#{Rails.application.config.secret_token}#{Time.now.to_i}")

    @@session = self
    reset(ticket.nil?)
  end

  def finished?
    self.progress == 100
  end

  def next_request
    return nil if current_job.nil?
    until (request = current_job.next_request(self)) do
      pending_jobs.shift
      reset(true) or break
    end
    jobs_completed = @initial_job_count - pending_jobs.length
    self.progress = ((jobs_completed.to_f  / @initial_job_count.to_f ) * 100).to_i
    request
  end
  alias :next :next_request  # Deprecated method name 'next'

  def current_request
    request = self.next_request
    if request && self.iterator_id.present?
      request = request.to_hash
      request.delete('xml_attributes')
      request.values.first['xml_attributes'] = {'iterator' => 'Continue', 'iteratorID' => self.iterator_id}
      request = QBWC::Request.new(request)
    end
    request
  end

  def response=(qbxml_response)
    begin
      QBWC.logger.info 'Parsing response.'
      response = QBWC.parser.from_qbxml(qbxml_response)["qbxml"]["qbxml_msgs_rs"].except("xml_attributes")
      response = response[response.keys.first]
      QBWC.logger.info 'Parsing headers.'
      parse_response_header(response)
      is_error = (self.error && self.status_severity == 'Error')
      QBWC.logger.info "Processing response."
      self.current_job.process_response(response, self, iterator_id.blank? && (!is_error || QBWC::on_error == 'continueOnError'))
      self.next_request unless is_error || self.iterator_id.present? # search next request
    rescue => e
      self.error = e.message
      QBWC.logger.warn "An error occured in QBWC::Session: #{e.message}"
      QBWC.logger.warn e.backtrace.join("\n")
    end
  end

  def save
  end

  def destroy
    self.freeze
    @@session = nil
  end

  protected

  attr_accessor :current_job, :iterator_id
  attr_writer :progress

  private

  def reset(reset_job = false)
    self.current_job = pending_jobs.first
    self.current_job.reset if reset_job && self.current_job
  end

  def pending_jobs
    @pending_jobs ||= QBWC.pending_jobs(@company, user)
  end

  def parse_response_header(response)
    self.iterator_id = nil
    self.error = nil
    self.status_code = nil
    self.status_severity = nil

    if response.is_a? Array
      response = response.find {|r| r.is_a?(Hash) && r['xml_attributes'] && r['xml_attributes']['statusCode'].to_i > 1} || response.first
    end
    return unless response.is_a?(Hash) && response['xml_attributes']

    @status_code, @status_severity, status_message, iterator_remaining_count, iterator_id = \
      response['xml_attributes'].values_at('statusCode', 'statusSeverity', 'statusMessage',
                                               'iteratorRemainingCount', 'iteratorID')
    QBWC.logger.info "Parsed headers. statusSeverity: '#{status_severity}'. statusCode: '#{@status_code}'"

    errmsg = "QBWC #{@status_severity.upcase}: #{@status_code} - #{status_message}"
    if @status_severity == 'Error' || @status_severity == 'Warn'
      @status_severity == 'Error' ? QBWC.logger.error(errmsg) : QBWC.logger.warn(errmsg)
      self.error = errmsg
    end

    self.iterator_id = iterator_id if iterator_remaining_count.to_i > 0 && @status_severity != 'Error'

  end
end

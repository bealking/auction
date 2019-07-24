include ForkBreak::Breakpoints

class BidLocker

  def initialize(user_id, price)
    @user_id = user_id
    @price = price

    # current bid price
    @bid_price = Redis::Counter.new('counter_bid_price', start: 16)
    @logs_key = 'lock_bid_logs'
    # all user bid logs

    # use set score to store price & user_id as {price: user_id}
    @bid_logs = Redis::SortedSet.new(@logs_key)
  end

  def increase
    key = @bid_price.value

    breakpoints << :before_lock
    if @bid_price.value.to_i == @price && @bid_logs[key.to_s].zero?
      @bid_logs[key.to_s] = @user_id
      puts "set #{@user_id} as price #{key}'s owner"
      @bid_price.increment(16)
    end
    breakpoints << :after_set

    p 'list bid result: '
    p '+++++++++++++'
    p Redis::SortedSet.new('lock_bid_logs').members(:with_scores => true)
    p '+++++++++++++'

    #puts "#{@user_id} bid the price #{key.to_i}"
  end

  def self.reset
    Redis::Counter.new('counter_bid_price').clear
    Redis::SortedSet.new('lock_bid_logs').clear
    Redis::SortedSet.new('unlock_bid_logs').clear
    Redis::Value.new('value_bid_price').delete
  end
end

def counter_after_synced_execution(with_lock)
  process1, process2 = 2.times.map do
    user_id = SecureRandom.random_number(9000) + 1000
    ForkBreak::Process.new do
      BidLocker.new(user_id, 16).increase
    end
  end

  puts 'start process1'
  process1.run_until(:after_set).wait
  puts 'process1 wait after set'

  puts 'start process2'
  process2.run_until(:before_lock).wait
  puts 'process2 wait before lock'

  process2.run_until(:after_set) && sleep(0.1)
  puts 'process2 wait after set'

  process1.finish.wait # Finish process1
  puts 'process1 done'
  p '---------------------'
  process2.finish.wait # Finish process2
  puts 'process2 done'

  p '---------------------'
  puts "next bid price is #{Redis::Counter.new('counter_bid_price').value}"
end

puts counter_after_synced_execution(true)

#! /bin/ruby -w

%q$Id: numplc.rb,v 1.67 2008/12/05 17:14:51 mitsuhide Exp uemura $ =~ /: (\S+),v (\S+)/
ProgName = $1
Revision = $2

require 'matrix'
require "curses"
require 'optparse'
ProgramConfig = Hash.new
opts = OptionParser.new
opts.on("-d", "--debug"){|v| ProgramConfig[:debug] = true}
opts.on("-b", "--bold"){|v| ProgramConfig[:bold] = true}
opts.parse!(ARGV)

file_name = ARGV.shift
if ProgramConfig[:debug]
  `rcsdiff numplc.rb > /dev/null 2>&1`
  status = $?
  if status == 0
    Mod = ""
  else
    Mod = "_mod"
  end
  ans_file = "a/" +
      file_name.sub(/^q\//, '').sub(/\.txt/, "_" + Revision + Mod + ".txt")
  $stdout = File::open(ans_file, "w+")
end

class Cell
  %w[cddts block row col fixed].each{|attr_name|
    attr_accessor attr_name
  }
  attr_reader   :init_fixed
  attr_accessor :i, :j if ProgramConfig[:debug]

  def initialize(cddts)
    @cddts = cddts
    @block = nil

    if(cddts.length == 1)
      @fixed = true
      @init_fixed = true
    else
      @fixed = false
      @init_fixed = false
    end
    @row = nil
    @col = nil
    if ProgramConfig[:debug]
      @i = @j = nil
    end
  end

  # Delete fixed values from candidates of unfixed cells row-wise,
  # column-wise and block-wise.
  def rm_fixed_values_from_cddts
    axes = [@row, @col, @block.to_a.flatten]
    axes.each{|axis|
      axis.each{|elm|
        next unless elm.fixed
        @cddts.delete(elm.cddts.first)
      }
    }

#   if ProgramConfig[:debug]
#     if @fixed == false and @cddts.length == 1
#       print "DEBUG: [#{@i}, #{@j}] = #{@cddts.first}\n"
#     end
#   end
    @fixed = true if(@cddts.length == 1)
  end

  # Gather the candidates of the row except the cell itself
  # and fix the value unless the candidates include that value.
  # Do the same thing column-wise and block-wise.
  def fix_if_cddt_is_uniq
    axes = [@row, @col, @block]
    axes.each{|axis|
      @cddts.each{|cddt|
        other_cell_cddts = []
        axis.map{|elm|
          next if elm == self
          other_cell_cddts.push(elm.cddts)
        }
        unless other_cell_cddts.flatten.include?(cddt)
          @cddts = [cddt]
#         if ProgramConfig[:debug]
#           print "DEBUG: [#{i}, #{j}] = #{cddts.first}\n" unless @fixed
#         end
          @fixed = true
        end
      }
    }
  end
  private :rm_fixed_values_from_cddts, :fix_if_cddt_is_uniq

  def narrow_cddt
    rm_fixed_values_from_cddts
    fix_if_cddt_is_uniq
  end
end

# Wanted to define a sub-class NumpclMtrx overriding initialize with super.
# But encountered an error saying "wrong number of arguments(3 for 0)
# so I gave up.
class Matrix
  attr_reader   :solved
  attr_accessor :blks

  def init
    @blks = Array.new
  end
  def each_row
    for i in 0...(self.column_size)
      yield self.row(i)
    end
  end
  def n_fixed
    num_fixed = 0
    self.map{|elm| num_fixed += 1 if elm.fixed}
    num_fixed
  end
  def solved?
    self.map{|elm|
      return false unless elm.fixed
    }
    return consistent?
  end
  def consistent?
    self.map{|elm|
      return false if elm.cddts.length == 0
    }
    # Check the consistency row-wise and column-wise.
    [self, self.transpose].each{|numplc|
      numplc.each_row{|row|
        row_cddts = []
        row.to_a.each{|elm|
          row_cddts.push(elm.cddts)
        }
        return false unless row_cddts.uniq.length == 9
      }
    }
    # Check the consistency block-wise.
    self.blks.each{|blk|
      blk_cddts = []
      blk.to_a.flatten.each{|elm|
        blk_cddts.push(elm.cddts)
      }
      return false unless blk_cddts.uniq.length == 9
    }
    return true
  end
end

class Block < Matrix 
  attr_accessor :ref_rows, :ref_cols

  def initialize(*args)
    super
    @ref_rows = nil
    @ref_cols = nil
  end
  def []=(i, j, x)
    @rows[i][j] = x
  end

  # Gather the candidates of the intersection of a block and a row.
  # Check if the candidate is included in the 6 cells in the rest of
  # the block and remove it from the candidates of the row if it is NOT.
  # Do the same thing column-wise.
  def rm_cddts_outof_blk
    axes = [@ref_rows, @ref_cols]
    axes.each{|axis|
      axis.each{|ref|
        intrsct_cddts = []
        (self.to_a.flatten & ref).each{|elm|
          intrsct_cddts.push(elm.cddts).flatten!.uniq!
        }
        six_cells_cddts = []
        (self.to_a.flatten - ref).each{|elm|
          six_cells_cddts.push(elm.cddts).flatten!.uniq!
        }
        intrsct_cddts.each{|cddt|
          unless six_cells_cddts.include?(cddt)
            (ref - self.to_a.flatten).each{|elm|
              elm.cddts.delete(cddt)
#             if ProgramConfig[:debug]
#               if elm.fixed == false and elm.cddts.length == 1
#                 print "DEBUG: [#{elm.i}, #{elm.j}] = #{elm.cddts.first}\n"
#               end
#             end
              elm.fixed = true if(elm.cddts.length == 1)
            }
          end
        }
      }
    }
  end
end

def parse(file_name)
  ary_of_ary = Array.new

  File.open(file_name){|q|
    while line = q.gets
      ary = Array.new
      line.sub!(/\s*#.*$/, '')          # Remove comments.
      next if line =~ /^\s*$/           # Skip blank lines.
      line.split(/\s+/).each{|elm|
        if elm =~ /\d+/
          ary.push(Cell.new([elm.to_i]))
        else
          ary.push(Cell.new([1, 2, 3, 4, 5, 6, 7, 8, 9]))
        end
      }
      ary_of_ary.push(ary)
    end
  }
  ary_of_ary
end

# Instanciate a matrix
mtrx_ary = parse(file_name)
mtrx = Matrix.rows(mtrx_ary)
mtrx.init

# Set the position in the matrix when tracing.
if ProgramConfig[:debug]
  for row in 0...(mtrx.column_size)
    for col in 0...(mtrx.row_size)
      mtrx[row, col].i = row
      mtrx[row, col].j = col
    end
  end
end

# Associate cells with a row and a column
for row in 0...(mtrx.column_size)
  for col in 0...(mtrx.row_size)
    mtrx[row, col].row = mtrx.row(row).to_a
    mtrx[row, col].col = mtrx.column(col).to_a
  end
end

# Generate a matrix of blocks
b_ary_of_ary = Array.new
for row in 0...3
  b_ary = Array.new
  for col in 0...3
    # Wanted to use Matrix#minor but it didn't work!
    blk = Block[[0,0,0],[0,0,0],[0,0,0]]
    for r in 0...3
      for c in 0...3
        blk[r, c] = mtrx[(row * 3 + r), (col * 3 + c)]
      end
    end
    b_ary.push(blk)
    mtrx.blks.push(blk)
  end
  b_ary_of_ary.push(b_ary)
end
b_mtrx = Matrix.rows(b_ary_of_ary)

# Associate cells with a block
for row in 0...(mtrx.row_size)
  for col in 0...(mtrx.column_size)
    mtrx[row, col].block = b_mtrx[row / 3, col / 3]
  end
end

# Associate blocks with 3 rows & 3 columns
for i in 0...3
  for j in 0...3
    b_mtrx[i, j].ref_rows = [   mtrx.row(i * 3    ).to_a,
                                mtrx.row(i * 3 + 1).to_a,
                                mtrx.row(i * 3 + 2).to_a]
    b_mtrx[i, j].ref_cols = [mtrx.column(j * 3    ).to_a,
                             mtrx.column(j * 3 + 1).to_a,
                             mtrx.column(j * 3 + 2).to_a]
  end
end

#
# Narrow candidates and find the answer.
#
n_fixed = n_fixed_prev = 0
for i in 1..(9 * 9)
  n_fixed_prev = n_fixed
  if ProgramConfig[:debug]
    puts "DEBUG: ### Candidates of each cell ###"
  end

  # Scan cell-wise.
  mtrx.map{|elm|
    if ProgramConfig[:debug]
      print "DEBUG: [#{elm.i}, #{elm.j}] -> "
      p elm.cddts
    end
    next if elm.fixed

#   elm.block.map{|elm|
#     print "[#{elm.i}, #{elm.j}]\n"
#     puts elm.cddts.first if elm.fixed
#   }
    elm.narrow_cddt
  }

  # Scan block-wise.
  b_mtrx.map{|blk|
    blk.rm_cddts_outof_blk
  }

  n_fixed = mtrx.n_fixed
  if ProgramConfig[:debug]
    print "DEBUG: #{n_fixed} cells fixed.\n"
  end

  break if n_fixed == (9 * 9) or n_fixed == n_fixed_prev
end

# Print the result
Curses::init_screen if ProgramConfig[:bold]
puts
mtrx.each_row{|row|
  for i in 0...(mtrx.column_size)
    if row[i].fixed
      if ProgramConfig[:bold]
        if row[i].init_fixed
          Curses::standout
          Curses::addstr(row[i].cddts.first.to_s)
          Curses::standend
        else
          Curses::addstr(row[i].cddts.first.to_s)
        end
      else
        print row[i].cddts.first
      end
    else
      if ProgramConfig[:bold]
        Curses::addstr("*")
      else
        print "*"
      end
    end
    if ProgramConfig[:bold]
      Curses::addstr(" ") unless i + 1 == mtrx.column_size
    else        
      print " " unless i + 1 == mtrx.column_size
    end
  end
  if ProgramConfig[:bold]
    Curses::addstr("\n")
  else
    print "\n"
  end
}

# Examine if it's solved.
puts
if mtrx.solved?
  puts "Solved."
else
  puts "Not solved."
end

if ProgramConfig[:bold]
  Curses::refresh
  Curses::close_screen
end

# $Log: numplc.rb,v $
# Revision 1.67  2008/12/05 17:14:51  mitsuhide
# Skip blank lines.
#
# Revision 1.66  2008/12/05 16:57:08  mitsuhide
# Remove commentss[?1;2c.
#
# Revision 1.65  2008/11/20 09:52:23  mitsuhide
# Changed how to define attr_accessor to  some fancy way.
#
# Revision 1.64  2008/08/27 23:00:21  mitsuhide
# Just changed comments.
#
# Revision 1.63  2008/08/27 22:50:31  mitsuhide
# Matrix#solved instance variable s[?1;2cwas useless, so deleted.
#
# Revision 1.62  2008/08/27 22:47:30  mitsuhide
# Created Matrix#consistent? and d let solved? call it.
#
# Revision 1.61  2008/08/16 15:15:52  mitsuhide
# REenamed nathe method name "narrow_cddt" to "rm_fixed_values_from_cddts"
# and privatized two methosds.
#
# Revision 1.60  2008/08/16 14:51:37  mitsuhide
# Shorten the code.
#
# Revision 1.59  2008/08/16 14:06:01  mitsuhide
# Moved debug print i n the loop again.
#
# Revision 1.58  2008/08/14 17:25:39  mitsuhide
# Commented degbug prints in Cell and Block class.
# Gathered them to the end o ff the calculation loop.
#
# Revision 1.57  2008/08/14 17:02:28  mitsuhide
# Removed an unused variable a--ll_fixed."all_fixed".
#
# Revision 1.56  2008/08/14 17:00:17  mitsuhide
# Modified the debug print in Block class.
#
# Revision 1.55  2008/08/14 16:45:20  mitsuhide
# Defined Block#rm_cddts_outof_blk.
#
# Revision 1.54  2008/08/14 09:58:36  mitsuhide
# Just changed comments.
#
# Revision 1.53  2008/08/14 09:56:20  mitsuhide
# Exit loop when # of fixed cells are not changed.
#
# Revision 1.52  2008/08/14 09:42:02  mitsuhide
# Defined Block class; sub-class of Matrix.
# Associated blocks iwith 3 rows and 3 columns.
#
# Revision 1.51  2008/08/02 05:57:13  mitsuhide
# Renamed the method Matrix::solved to solved? because @solved variable
# exists and it cuauseds a wairning.
#
# Revision 1.50  2008/08/02 05:51:42  mitsuhide
# Restored redirection to a file on debugging mode.
#
# Revision 1.49  2008/08/02 05:05:31  mitsuhide
# Changed the shebang line because this environment won't accept
# ruby's -w option.
#
# Revision 1.48  2008/08/02 04:16:21  mitsuhide
# Out commented unused codes temporarily.
#
# Revision 1.47  2008/08/02 02:57:36  mitsuhide
# Deleted redirection when debugging.
#
# Revision 1.46  2008/08/02 02:06:53  mitsuhide
# Changed the way to extract the minor of the matrix.
#
# Revision 1.45  2008/07/22 15:41:24  mitsuhide
# Added suome debug prints but disabled.
#
# Revision 1.44  2008/07/21 13:39:22  mitsuhide
# Associate blocks with 3 rows & 3 columns.
#
# Revision 1.43  2008/07/21 05:00:13  mitsuhide
# Fixed the bug of the emethod 'checuk_uniq' and renamed.
#
# Revision 1.42  2008/07/21 02:22:49  mitsuhide
# Just Mmodified commnents.
#
# Revision 1.41  2008/07/17 06:34:24  uemura
# Removed $ID$ from $LOG$. It was too misleading!
#
# Revision 1.40  2008/07/17 06:29:35  uemura
# row_size and column_size were misplaced.
#
# Revision 1.39  2008/07/17 06:23:41  uemura
# Deleted an obsolete comment.
#
# Revision 1.38  2008/07/17 06:14:22  uemura
# Changed the access mode of $stdout.
# The output of the modified script should always be updated.
#
# Revision 1.37  2008/07/17 05:22:42  uemura
# Implemented an iterator Matrix#each_row.
#
# Revision 1.36  2008/07/14 01:16:00  uemura
# Extended a method "check_uniq" row-wise and column-wise.
# Block-wise was not enough!
#
# Revision 1.35  2008/07/08 01:44:15  uemura
# Required "curses" and added bold option.
#
# Revision 1.34  2008/06/03 04:42:46  uemura
# Break if n_fixed == 9 * 9
#
# Revision 1.33  2008/06/03 03:14:12  uemura
# Q{2,3,x} can be solved but Q0 can't.
# Temporarily change the loop condition.
#
# Revision 1.32  2008/06/03 03:00:37  uemura
# Rolled back the break loop condition.
#
# Revision 1.31  2008/06/03 02:58:30  uemura
# Replaced obsolete method 'to_a' with Kernel#Array
#
# Revision 1.30  2008/06/02 07:33:07  uemura
# Added a suffix "_mod" to debug output file again.
#
# Revision 1.29  2008/06/02 02:23:24  uemura
# Q{4,5,6} won't be solved and loops infinitely.
# Temporarily change the break loop condition.
#
# Revision 1.27  2008/06/02 01:56:34  uemura
# Gave up to add a suffix '_Mod'
#
# Revision 1.26  2008/06/02 01:54:10  uemura
# Converted $? to Integer.
#
# Revision 1.25  2008/06/02 01:44:54  uemura
# Added suffix "_mod" when script is modified.
#
# Revision 1.24  2008/05/30 07:50:29  uemura
# Ask the object how many cells are fixed!
#
# Revision 1.23  2008/05/30 07:23:29  uemura
# Modified a format of debug print.
#
# Revision 1.22  2008/05/30 07:17:28  uemura
# Unified all the options for debugging.
#
# Revision 1.21  2008/05/30 06:31:12  uemura
# Changed a format of debug output.
#
# Revision 1.20  2008/05/30 03:21:18  uemura
# Changed the watch point to check terminal state instead of initial state.
#
# Revision 1.19  2008/05/30 02:34:00  uemura
# Removed debug codes that prints object ID's check and diff current and
# previous log files.
#
# Revision 1.18  2008/05/30 01:11:03  uemura
# Made 'ans/' directory and dump all to answer file.
#
# Revision 1.17  2008/05/29 06:12:52  uemura
# Set the position in the matrix when tracing.
#
# Revision 1.16  2008/05/26 08:08:06  uemura
# Moved 'check_uniq' near 'narrow_cddt'
#
# Revision 1.15  2008/05/26 06:30:25  uemura
# Check fixed value instead of cells when confirming if it's solved.
#
# Revision 1.14  2008/05/26 03:30:08  uemura
# Check blocks when confirminig it's solved.
#
# Revision 1.13  2008/05/23 07:50:46  uemura
# Extended Matrix class to confirm it's solved, checking only rows & columns.
#
# Revision 1.12  2008/05/12 08:04:37  uemura
# Don't skip fixed cells on check_uniq
#
# Revision 1.11  2008/05/12 06:46:03  uemura
# Added watch option temporarily.
#
# Revision 1.10  2008/05/09 05:50:09  uemura
# Redirect to file when --debug is specified.
#
# Revision 1.9  2008/05/09 05:10:53  uemura
# Get $Id into variables.
#
# Revision 1.8  2008/05/08 07:42:01  uemura
# Won't print " " at the end of rows.
#
# Revision 1.7  2008/05/08 07:39:39  uemura
# Added a method "check_uniq"
#
# Revision 1.6  2008/04/28 06:21:45  uemura
# Symbolize undefined cell with "*" instead of "?" for output.
#
# Revision 1.5  2008/04/28 06:20:58  uemura
# Print candidates for debugging.
#
# Revision 1.4  2008/04/28 05:25:33  uemura
# Renamed the variable "no_fixed*"
#
# Revision 1.3  2008/04/22 07:26:43  uemura
# Moved printing part of no_fixed to DEBUG option block.
#
# Revision 1.2  2008/04/22 07:14:39  uemura
# Stop solving when candidate narrowing won't progress.
#
# Revision 1.1  2008/04/22 06:39:14  uemura
# Initial revision
#

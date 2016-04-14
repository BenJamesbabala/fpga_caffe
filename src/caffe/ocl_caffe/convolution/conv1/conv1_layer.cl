#define NUM_DATA_ROWS (227)
#define NUM_DATA_COLS (227)
#define PAD           (0)
#define NUM_MASK_ROWS (11)
#define NUM_MASK_COLS (11)
#define STRIDE (4)
#define IN_CHANNEL 3
#define OUT_CHANNEL 96
#define K_CHANNEL 3
#define GROUPS 1
#define TOP_NUM 1 
#define K_NUM 96
#define O_G 96
#define K_G 3
#define BURST 3 

#define NUM_OUT_COLS (((NUM_DATA_COLS - NUM_MASK_COLS + (2*PAD) )/ (STRIDE)) + 1)
#define NUM_OUT_ROWS (((NUM_DATA_ROWS - NUM_MASK_ROWS + (2*PAD) )/ (STRIDE)) + 1)

#define DATA_SIZE_KERN      TOP_NUM * IN_CHANNEL * (NUM_DATA_ROWS) * (NUM_DATA_COLS)
#define FILTER_SIZE_KERN    k_NUM * K_CHANNEL * NUM_MASK_ROWS * NUM_MASK_COLS
#define OUTPUT_SIZE_KERN    TOP_NUM * OUT_CHANNEL * NUM_OUT_ROWS * NUM_OUT_COLS

__kernel __attribute__ ((reqd_work_group_size(1, 1, 1)))
void conv1_layer(__global float *a, __global float *b, __global float *output)
{
  __local float window[BURST * NUM_MASK_ROWS * NUM_MASK_COLS];
  __local float input[NUM_DATA_COLS];
  __local float bufout[NUM_OUT_ROWS * NUM_OUT_COLS]; 

  int o_head = 0;
  int k_head = 0;
  int in_y = 0;
  int in_x = 0;
  int out_idx_t = 0;
  int data_idx_t = 0;
  int filter_idx_t = 0;
  int out_idx = 0;
  int data_idx = 0;
  int filter_idx = 0;

  int o = get_global_id(0);
  
  int idx_y[NUM_MASK_ROWS][NUM_OUT_ROWS];
  int idx_x[NUM_OUT_COLS][NUM_MASK_COLS];

  for (int p = 0; p < NUM_MASK_ROWS; ++p)
    for (int y = 0; y < NUM_OUT_ROWS; ++y)
      idx_y[p][y] = y * STRIDE - PAD + p;

  for (int x = 0; x < NUM_OUT_COLS; ++x)
    for (int q = 0; q < NUM_MASK_COLS; ++q)
      idx_x[x][q] = x * STRIDE - PAD + q;

  for (int i = 0; i < NUM_OUT_ROWS * NUM_OUT_COLS; ++i)
    bufout[i] = 0;

  float temp[NUM_MASK_COLS];

  filter_idx_t = (o + o_head) * K_CHANNEL;
      
  async_work_group_copy(window, b + (filter_idx_t) * NUM_MASK_ROWS * NUM_MASK_COLS,  BURST * NUM_MASK_ROWS * NUM_MASK_COLS, 0);    

  for (int i = 0; i < BURST; ++i) {
    filter_idx_t = i * NUM_MASK_ROWS * NUM_MASK_COLS;
    for (int y = 0; y < NUM_OUT_ROWS; ++y) {
      for (int p = 0; p < NUM_MASK_ROWS; ++p) {
        in_y = idx_y[p][y];
        if(in_y >= 0 && in_y < NUM_DATA_ROWS) {
          async_work_group_copy(input, a + (i * NUM_DATA_ROWS + in_y) * NUM_DATA_COLS, NUM_DATA_COLS, 0);
          __attribute__((xcl_pipeline_loop))
          for (int x = 0; x < NUM_OUT_COLS; ++x) {
            for (int q = 0; q < NUM_MASK_COLS; ++q) {
              in_x = idx_x[x][q];
              out_idx = y * NUM_OUT_COLS + x;
              data_idx = in_x;
              filter_idx = filter_idx_t + p * NUM_MASK_COLS + q;
              if(in_x >= 0 && in_x < NUM_DATA_COLS) {
                temp[q] = input[data_idx] * window[filter_idx];
              }
              else
                temp[q] = 0;
            }
            for (int q = 0; q < NUM_MASK_COLS; ++q)
              bufout[out_idx] += temp[q];
          }
        }
      }
    }
  }
  async_work_group_copy(output + o * NUM_OUT_ROWS * NUM_OUT_COLS, bufout, NUM_OUT_ROWS * NUM_OUT_COLS, 0);
    
  return;
}
#ifndef CONV_LAYER_CUH
#define CONV_LAYER_CUH

#include "cuda.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include "caffe/blob.hpp"

using namespace std;


namespace caffe {

// low-memory convolution

/*
inputs: 
  bottom_data
  top_data
  filters = "weight"
  num_output //#filters
  num_channels = CHANNELS_
  height_in = HEIGHT_
  width_in = WIDTH_
  height_out
  width_out
  stride //same for x and y
  kernelSize //convolution filter dim. same for x and y... ignores depth
  imgID "n" //within batch
  groupID "g" //typically 0 or 1

  float* bottom //input (base ptr for beginning of batch)
  float* top    //output
*/



// each thread owns an output pixel and a filter.
template <typename Dtype>
__global__ void Conv_gpu_lowMem_kernel(const Dtype* bottom_data, Dtype* top_data, const Dtype* filters,
                                       int stride, int kernelSize, int num_channels, int height_in, int width_in,
                                       int num_output, int height_out, int width_out,
                                       int imgID, int numGroups, int groupID)
{

    int top_data_length = 50 * num_output * height_out * width_out; 

    //top-left anchor in input image:
    int x = (blockIdx.x*blockDim.x + threadIdx.x);
    int y = (blockIdx.y*blockDim.y + threadIdx.y);

    int num_filters_per_group = num_output / numGroups; 
    int f = (blockIdx.z*blockDim.z + threadIdx.z) + (num_filters_per_group*groupID); //filter ID
    int num_channels_per_group = num_channels / numGroups;
    int num_output_per_group = num_output / numGroups;

    Dtype output_px = 0.0f; //calculate in this register, then write to output buffer

    int filterIdx_base = f * (num_channels_per_group * kernelSize * kernelSize);

    int inputIdx_base = imgID   * (num_channels * height_in * width_in) +
                        groupID * (num_channels_per_group * height_in * width_in);

    if( (x < width_out) && (y < height_out) && (f < num_output) )
    //if( (x < 5) && (y < 5) && (f < 5) ) //test
    {

        for(int ch=0; ch < num_channels_per_group; ch++)
        {
            for(int yLocal=0; yLocal < kernelSize; yLocal++)
            {
                for(int xLocal=0; xLocal < kernelSize; xLocal++)
                {

    #if 1
                    //TODO: consider stride in inputIdx
                    int inputIdx = inputIdx_base +
                                   ch                   * (height_in * width_in) + 
                                   (y*stride + yLocal)  * (width_in) + 
                                   (x*stride + xLocal);

                    //index of current element in filter f
                    int filterIdx = filterIdx_base +
                                    ch     * (kernelSize * kernelSize) +
                                    yLocal * (kernelSize) + 
                                    xLocal;
    #endif
                    output_px += bottom_data[inputIdx] * filters[filterIdx]; 
                }
            }
        }

        int outputIdx = imgID   * (num_output * height_out * width_out) +
                        //groupID * (num_output_per_group * height_out * width_out) +
                        f       * (height_out * width_out) +
                        y       * (width_out) + x; 

        //assert(outputIdx < top_data_length); 
        if(outputIdx >= top_data_length){
            printf("out of top_data bounds\n");
        }


        top_data[outputIdx] = output_px;
    }
}


// wrapper ... launches the conv kernel.
// for now, this processes ONE IMAGE (one item in a batch)
template <typename Dtype>
void Conv_gpu_lowMem(const vector<Blob<Dtype>*>& bottom, vector<Blob<Dtype>*>* top, const Dtype* filters,
                     int stride, int kernelSize, int num_channels, int height_in, int width_in,
                     int num_output, int height_out, int width_out,
                     int imgID, int numGroups, int groupID)
{
    dim3 grid;
    dim3 block;
    block.x = 16;
    block.y = 16;
    block.z = 4; //tune?
    int nx = width_out / (block.x*1); 
    int ny = height_out / (block.y*1);
    int nz = num_output / (block.z * numGroups); // # of 3D filters
    grid.x = (width_out % block.x == 0) ? nx : nx+1;
    grid.y = (height_out % block.y == 0) ? ny : ny+1;
    grid.z = (num_output % block.z == 0) ? nz : nz+1;

    const Dtype* bottom_data = bottom[0]->gpu_data();
    Dtype* top_data = (*top)[0]->mutable_gpu_data();

    //int top_data_length_correct = (*top)[0]->count();
    //int top_data_length_ours = 50 * num_output * height_out * width_out;
    //printf("top_data_length_correct=%d, top_data_length_ours=%d \n", top_data_length_correct, top_data_length_ours);

    Conv_gpu_lowMem_kernel <<< grid, block >>> (bottom_data, top_data, filters,
                                                stride, kernelSize, num_channels, height_in, width_in,
                                                num_output, height_out, width_out,
                                                imgID, numGroups, groupID);    

    CUDA_CHECK(cudaDeviceSynchronize());

/*
    printf(" stride=%d, kernelSize=%d, num_channels=%d, height_in=%d, width_in=%d,"
            "num_output=%d, height_out=%d, width_out=%d,"
            "imgID=%d, numGroups=%d, groupID=%d \n", stride, kernelSize, num_channels, height_in, width_in,
                                                num_output, height_out, width_out,
                                                imgID, numGroups, groupID);
*/
}

void hello_cuda()
{
}

template <typename Dtype>
//void hello_cuda_template()
void hello_cuda_template(const vector<Blob<Dtype>*>& bottom)
{

}


} // close Caffe class

#endif

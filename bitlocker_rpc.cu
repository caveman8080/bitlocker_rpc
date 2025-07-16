#include <cuda_runtime.h>
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <stdexcept>
#include <iomanip>
#include <cstdint>
#include <cstring>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <getopt.h>
#include <fstream>

#define CUDA_CHECK(call) \
    { cudaError_t err = call; if (err != cudaSuccess) { \
        std::cerr << "CUDA error: " << cudaGetErrorString(err) << std::endl; exit(1); } }

__device__ __constant__ uint32_t k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

__device__ __constant__ unsigned int rcon[11] = {
    0x00000000, 0x01000000, 0x02000000, 0x04000000, 0x08000000,
    0x10000000, 0x20000000, 0x40000000, 0x80000000, 0x1B000000, 0x36000000
};

__device__ __constant__ unsigned int TS0[256] = {
    0xC66363A5U, 0xF87C7C84U, 0xEE777799U, 0xF67B7B8DU, 0xFFF2F20DU, 0xD66B6BBDU, 0xDE6F6FB1U, 0x91C5C554U, 
    0x60303050U, 0x02010103U, 0xCE6767A9U, 0x562B2B7DU, 0xE7FEFE19U, 0xB5D7D762U, 0x4DABABE6U, 0xEC76769AU, 
    0x8FCACA45U, 0x1F82829DU, 0x89C9C940U, 0xFA7D7D87U, 0xEFFAFA15U, 0xB25959EBU, 0x8E4747C9U, 0xFBF0F00BU, 
    0x41ADADECU, 0xB3D4D467U, 0x5FA2A2FDU, 0x45AFAFEAU, 0x239C9CBFU, 0x53A4A4F7U, 0xE4727296U, 0x9BC0C05BU, 
    0x75B7B7C2U, 0xE1FDFD1CU, 0x3D9393AEU, 0x4C26266AU, 0x6C36365AU, 0x7E3F3F41U, 0xF5F7F702U, 0x83CCCC4FU, 
    0x6834345CU, 0x51A5A5F4U, 0xD1E5E534U, 0xF9F1F108U, 0xE2717193U, 0xABD8D873U, 0x62313153U, 0x2A15153FU, 
    0x0804040CU, 0x95C7C752U, 0x46232365U, 0x9DC3C35EU, 0x30181828U, 0x379696A1U, 0x0A05050FU, 0x2F9A9AB5U, 
    0x0E070709U, 0x24121236U, 0x1B80809BU, 0xDFE2E23DU, 0xCDEBEB26U, 0x4E272769U, 0x7FB2B2CDU, 0xEA75759FU, 
    0x1209091BU, 0x1D83839EU, 0x582C2C74U, 0x341A1A2EU, 0x361B1B2DU, 0xDC6E6EB2U, 0xB45A5AEEU, 0x5BA0A0FBU, 
    0xA45252F6U, 0x763B3B4DU, 0xB7D6D661U, 0x7DB3B3CEU, 0x5229297BU, 0xDDE3E33EU, 0x5E2F2F71U, 0x13848497U, 
    0xA65353F5U, 0xB9D1D168U, 0x00000000U, 0xC1EDED2CU, 0x40202060U, 0xE3FCFC1FU, 0x79B1B1C8U, 0xB65B5BEDU, 
    0xD46A6ABEU, 0x8DCBCB46U, 0x67BEBED9U, 0x7239394BU, 0x944A4ADEU, 0x984C4CD4U, 0xB05858E8U, 0x85CFCF4AU, 
    0xBBD0D06BU, 0xC5EFEF2AU, 0x4FAAAAE5U, 0xEDFBFB16U, 0x864343C5U, 0x9A4D4DD7U, 0x66333355U, 0x11858594U, 
    0x8A4545CFU, 0xE9F9F910U, 0x04020206U, 0xFE7F7F81U, 0xA05050F0U, 0x783C3C44U, 0x259F9FBAU, 0x4BA8A8E3U, 
    0xA25151F3U, 0x5DA3A3FEU, 0x804040C0U, 0x058F8F8AU, 0x3F9292ADU, 0x219D9DBCU, 0x70383848U, 0xF1F5F504U, 
    0x63BCBCDFU, 0x77B6B6C1U, 0xAFDADA75U, 0x42212163U, 0x20101030U, 0xE5FFFF1AU, 0xFDF3F30EU, 0xBFD2D26DU, 
    0x81CDCD4CU, 0x180C0C14U, 0x26131335U, 0xC3ECEC2FU, 0xBE5F5FE1U, 0x359797A2U, 0x884444CCU, 0x2E171739U, 
    0x93C4C457U, 0x55A7A7F2U, 0xFC7E7E82U, 0x7A3D3D47U, 0xC86464ACU, 0xBA5D5DE7U, 0x3219192BU, 0xE6737395U, 
    0xC06060A0U, 0x19818198U, 0x9E4F4FD1U, 0xA3DCDC7FU, 0x44222266U, 0x542A2A7EU, 0x3B9090ABU, 0x0B888883U, 
    0x8C4646CAU, 0xC7EEEE29U, 0x6BB8B8D3U, 0x2814143CU, 0xA7DEDE79U, 0xBC5E5EE2U, 0x160B0B1DU, 0xADDBDB76U, 
    0xDBE0E03BU, 0x64323256U, 0x743A3A4EU, 0x140A0A1EU, 0x924949DBU, 0x0C06060AU, 0x4824246CU, 0xB85C5CE4U, 
    0x9FC2C25DU, 0xBDD3D36EU, 0x43ACACEFU, 0xC46262A6U, 0x399191A8U, 0x319595A4U, 0xD3E4E437U, 0xF279798BU, 
    0xD5E7E732U, 0x8BC8C843U, 0x6E373759U, 0xDA6D6DB7U, 0x018D8D8CU, 0xB1D5D564U, 0x9C4E4ED2U, 0x49A9A9E0U, 
    0xD86C6CB4U, 0xAC5656FAU, 0xF3F4F407U, 0xCFEAEA25U, 0xCA6565AFU, 0xF47A7A8EU, 0x47AEAEE9U, 0x10080818U, 
    0x6FBABAD5U, 0xF0787888U, 0x4A25256FU, 0x5C2E2E72U, 0x381C1C24U, 0x57A6A6F1U, 0x73B4B4C7U, 0x97C6C651U, 
    0xCBE8E823U, 0xA1DDDD7CU, 0xE874749CU, 0x3E1F1F21U, 0x964B4BDDU, 0x61BDBDDCU, 0x0D8B8B86U, 0x0F8A8A85U, 
    0xE0707090U, 0x7C3E3E42U, 0x71B5B5C4U, 0xCC6666AAU, 0x904848D8U, 0x06030305U, 0xF7F6F601U, 0x1C0E0E12U, 
    0xC26161A3U, 0x6A35355FU, 0xAE5757F9U, 0x69B9B9D0U, 0x17868691U, 0x99C1C158U, 0x3A1D1D27U, 0x279E9EB9U, 
    0xD9E1E138U, 0xEBF8F813U, 0x2B9898B3U, 0x22111133U, 0xD26969BBU, 0xA9D9D970U, 0x078E8E89U, 0x339494A7U, 
    0x2D9B9BB6U, 0x3C1E1E22U, 0x15878792U, 0xC9E9E920U, 0x87CECE49U, 0xAA5555FFU, 0x50282878U, 0xA5DFDF7AU, 
    0x038C8C8FU, 0x59A1A1F8U, 0x09898980U, 0x1A0D0D17U, 0x65BFBFDAU, 0xD7E6E631U, 0x844242C6U, 0xD06868B8U, 
    0x824141C3U, 0x299999B0U, 0x5A2D2D77U, 0x1E0F0F11U, 0x7BB0B0CBU, 0xA85454FCU, 0x6DBBBBD6U, 0x2C16163AU
};

__device__ __constant__ unsigned int TS1[256] = {
    0xA5C66363U, 0x84F87C7CU, 0x99EE7777U, 0x8DF67B7BU, 0x0DFFF2F2U, 0xBDD66B6BU, 0xB1DE6F6FU, 0x5491C5C5U, 
    0x50603030U, 0x03020101U, 0xA9CE6767U, 0x7D562B2BU, 0x19E7FEFEU, 0x62B5D7D7U, 0xE64DABABU, 0x9AEC7676U, 
    0x458FCACAU, 0x9D1F8282U, 0x4089C9C9U, 0x87FA7D7DU, 0x15EFFAFAU, 0xEBB25959U, 0xC98E4747U, 0x0BFBF0F0U, 
    0xEC41ADADU, 0x67B3D4D4U, 0xFD5FA2A2U, 0xEA45AFAFU, 0xBF239C9CU, 0xF753A4A4U, 0x96E47272U, 0x5B9BC0C0U, 
    0xC275B7B7U, 0x1CE1FDFDU, 0xAE3D9393U, 0x6A4C2626U, 0x5A6C3636U, 0x417E3F3FU, 0x02F5F7F7U, 0x4F83CCCCU, 
    0x5C683434U, 0xF451A5A5U, 0x34D1E5E5U, 0x08F9F1F1U, 0x93E27171U, 0x73ABD8D8U, 0x53623131U, 0x3F2A1515U, 
    0x0C080404U, 0x5295C7C7U, 0x65462323U, 0x5E9DC3C3U, 0x28301818U, 0xA1379696U, 0x0F0A0505U, 0xB52F9A9AU, 
    0x090E0707U, 0x36241212U, 0x9B1B8080U, 0x3DDFE2E2U, 0x26CDEBEBU, 0x694E2727U, 0xCD7FB2B2U, 0x9FEA7575U, 
    0x1B120909U, 0x9E1D8383U, 0x74582C2CU, 0x2E341A1AU, 0x2D361B1BU, 0xB2DC6E6EU, 0xEEB45A5AU, 0xFB5BA0A0U, 
    0xF6A45252U, 0x4D763B3BU, 0x61B7D6D6U, 0xCE7DB3B3U, 0x7B522929U, 0x3EDDE3E3U, 0x715E2F2FU, 0x97138484U, 
    0xF5A65353U, 0x68B9D1D1U, 0x00000000U, 0x2CC1EDEDU, 0x60402020U, 0x1FE3FCFCU, 0xC879B1B1U, 0xEDB65B5BU, 
    0xBED46A6AU, 0x468DCBCBU, 0xD967BEBEU, 0x4B723939U, 0xDE944A4AU, 0xD4984C4CU, 0xE8B05858U, 0x4A85CFCFU, 
    0x6BBBD0D0U, 0x2AC5EFEFU, 0xE54FAAAAU, 0x16EDFBFBU, 0xC5864343U, 0xD79A4D4DU, 0x55663333U, 0x94118585U, 
    0xCF8A4545U, 0x10E9F9F9U, 0x06040202U, 0x81FE7F7FU, 0xF0A05050U, 0x44783C3CU, 0xBA259F9FU, 0xE34BA8A8U, 
    0xF3A25151U, 0xFE5DA3A3U, 0xC0804040U, 0x8A058F8FU, 0xAD3F9292U, 0xBC219D9DU, 0x48703838U, 0x04F1F5F5U, 
    0xDF63BCBCU, 0xC177B6B6U, 0x75AFDADAU, 0x63422121U, 0x30201010U, 0x1AE5FFFFU, 0x0EFDF3F3U, 0x6DBFD2D2U, 
    0x4C81CDCDU, 0x14180C0CU, 0x35261313U, 0x2FC3ECECU, 0xE1BE5F5FU, 0xA2359797U, 0xCC884444U, 0x392E1717U, 
    0x5793C4C4U, 0xF255A7A7U, 0x82FC7E7EU, 0x477A3D3DU, 0xACC86464U, 0xE7BA5D5DU, 0x2B321919U, 0x95E67373U, 
    0xA0C06060U, 0x98198181U, 0xD19E4F4FU, 0x7FA3DCDCU, 0x66442222U, 0x7E542A2AU, 0xAB3B9090U, 0x830B8888U, 
    0xCA8C4646U, 0x29C7EEEEU, 0xD36BB8B8U, 0x3C281414U, 0x79A7DEDEU, 0xE2BC5E5EU, 0x1D160B0BU, 0x76ADDBDBU, 
    0x3BDBE0E0U, 0x56643232U, 0x4E743A3AU, 0x1E140A0AU, 0xDB924949U, 0x0A0C0606U, 0x6C482424U, 0xE4B85C5CU, 
    0x5D9FC2C2U, 0x6EBDD3D3U, 0xEF43ACACU, 0xA6C46262U, 0xA8399191U, 0xA4319595U, 0x37D3E4E4U, 0x8BF27979U, 
    0x32D5E7E7U, 0x438BC8C8U, 0x596E3737U, 0xB7DA6D6DU, 0x8C018D8DU, 0x64B1D5D5U, 0xD29C4E4EU, 0xE049A9A9U, 
    0xB4D86C6CU, 0xFAAC5656U, 0x07F3F4F4U, 0x25CFEAEAU, 0xAFCA6565U, 0x8EF47A7AU, 0xE947AEAEU, 0x18100808U, 
    0xD56FBABAU, 0x88F07878U, 0x6F4A2525U, 0x725C2E2EU, 0x24381C1CU, 0xF157A6A6U, 0xC773B4B4U, 0x5197C6C6U, 
    0x23CBE8E8U, 0x7CA1DDDDU, 0x9CE87474U, 0x213E1F1FU, 0xDD964B4BU, 0xDC61BDBDU, 0x860D8B8BU, 0x850F8A8AU, 
    0x90E07070U, 0x427C3E3EU, 0xC471B5B5U, 0xAACC6666U, 0xD8904848U, 0x05060303U, 0x01F7F6F6U, 0x121C0E0EU, 
    0xA3C26161U, 0x5F6A3535U, 0xF9AE5757U, 0xD069B9B9U, 0x91178686U, 0x5899C1C1U, 0x273A1D1DU, 0xB9279E9EU, 
    0x38D9E1E1U, 0x13EBF8F8U, 0xB32B9898U, 0x33221111U, 0xBBD26969U, 0x70A9D9D9U, 0x89078E8EU, 0xA7339494U, 
    0xB62D9B9BU, 0x223C1E1EU, 0x92158787U, 0x20C9E9E9U, 0x4987CECEU, 0xFFAA5555U, 0x78502828U, 0x7AA5DFDFU, 
    0x8F038C8CU, 0xF859A1A1U, 0x80098989U, 0x171A0D0DU, 0xDA65BFBFU, 0x31D7E6E6U, 0xC6844242U, 0xB8D06868U, 
    0xC3824141U, 0xB0299999U, 0x775A2D2DU, 0x111E0F0FU, 0xCB7BB0B0U, 0xFCA85454U, 0xD66DBBBBU, 0x3A2C1616U
};

__device__ __constant__ unsigned int TS2[256] = {
    0x63A5C663U, 0x7C84F87CU, 0x7799EE77U, 0x7B8DF67BU, 0xF20DFFF2U, 0x6BBDD66BU, 0x6FB1DE6FU, 0xC55491C5U, 
    0x30506030U, 0x01030201U, 0x67A9CE67U, 0x2B7D562BU, 0xFE19E7FEU, 0xD762B5D7U, 0xABE64DABU, 0x769AEC76U, 
    0xCA458FCAU, 0x829D1F82U, 0xC94089C9U, 0x7D87FA7DU, 0xFA15EFFAU, 0x59EBB259U, 0x47C98E47U, 0xF00BFBF0U, 
    0xADEC41ADU, 0xD467B3D4U, 0xA2FD5FA2U, 0xAFEA45AFU, 0x9CBF239CU, 0xA4F753A4U, 0x7296E472U, 0xC05B9BC0U, 
    0xB7C275B7U, 0xFD1CE1FDU, 0x93AE3D93U, 0x266A4C26U, 0x365A6C36U, 0x3F417E3FU, 0xF702F5F7U, 0xCC4F83CCU, 
    0x345C6834U, 0xA5F451A5U, 0xE534D1E5U, 0xF108F9F1U, 0x7193E271U, 0xD873ABD8U, 0x31536231U, 0x153F2A15U, 
    0x040C0804U, 0xC75295C7U, 0x23654623U, 0xC35E9DC3U, 0x18283018U, 0x96A13796U, 0x050F0A05U, 0x9AB52F9AU, 
    0x07090E07U, 0x12362412U, 0x809B1B80U, 0xE23DDFE2U, 0xEB26CDEBU, 0x27694E27U, 0xB2CD7FB2U, 0x759FEA75U, 
    0x091B1209U, 0x839E1D83U, 0x2C74582CU, 0x1A2E341AU, 0x1B2D361BU, 0x6EB2DC6EU, 0x5AEEB45AU, 0xA0FB5BA0U, 
    0x52F6A452U, 0x3B4D763BU, 0xD661B7D6U, 0xB3CE7DB3U, 0x297B5229U, 0xE33EDDE3U, 0x2F715E2FU, 0x84971384U, 
    0x53F5A653U, 0xD168B9D1U, 0x00000000U, 0xED2CC1EDU, 0x20604020U, 0xFC1FE3FCU, 0xB1C879B1U, 0x5BEDB65BU, 
    0x6ABED46AU, 0xCB468DCBU, 0xBED967BEU, 0x394B7239U, 0x4ADE944AU, 0x4CD4984CU, 0x58E8B058U, 0xCF4A85CFU, 
    0xD06BBBD0U, 0xEF2AC5EFU, 0xAAE54FAAU, 0xFB16EDFBU, 0x43C58643U, 0x4DD79A4DU, 0x33556633U, 0x85941185U, 
    0x45CF8A45U, 0xF910E9F9U, 0x02060402U, 0x7F81FE7FU, 0x50F0A050U, 0x3C44783CU, 0x9FBA259FU, 0xA8E34BA8U, 
    0x51F3A251U, 0xA3FE5DA3U, 0x40C08040U, 0x8F8A058FU, 0x92AD3F92U, 0x9DBC219DU, 0x38487038U, 0xF504F1F5U, 
    0xBCDF63BCU, 0xB6C177B6U, 0xDA75AFDAU, 0x21634221U, 0x10302010U, 0xFF1AE5FFU, 0xF30EFDF3U, 0xD26DBFD2U, 
    0xCD4C81CDU, 0x0C14180CU, 0x13352613U, 0xEC2FC3ECU, 0x5FE1BE5FU, 0x97A23597U, 0x44CC8844U, 0x17392E17U, 
    0xC45793C4U, 0xA7F255A7U, 0x7E82FC7EU, 0x3D477A3DU, 0x64ACC864U, 0x5DE7BA5DU, 0x192B3219U, 0x7395E673U, 
    0x60A0C060U, 0x81981981U, 0x4FD19E4FU, 0xDC7FA3DCU, 0x22664422U, 0x2A7E542AU, 0x90AB3B90U, 0x88830B88U, 
    0x46CA8C46U, 0xEE29C7EEU, 0xB8D36BB8U, 0x143C2814U, 0xDE79A7DEU, 0x5EE2BC5EU, 0x0B1D160BU, 0xDB76ADDBU, 
    0xE03BDBE0U, 0x32566432U, 0x3A4E743AU, 0x0A1E140AU, 0x49DB9249U, 0x060A0C06U, 0x246C4824U, 0x5CE4B85CU, 
    0xC25D9FC2U, 0xD36EBDD3U, 0xACEF43ACU, 0x62A6C462U, 0x91A83991U, 0x95A43195U, 0xE437D3E4U, 0x798BF279U, 
    0xE732D5E7U, 0xC8438BC8U, 0x37596E37U, 0x6DB7DA6DU, 0x8D8C018DU, 0xD564B1D5U, 0x4ED29C4EU, 0xA9E049A9U, 
    0x6CB4D86CU, 0x56FAAC56U, 0xF407F3F4U, 0xEA25CFEAU, 0x65AFCA65U, 0x7A8EF47AU, 0xAEE947AEU, 0x08181008U, 
    0xBAD56FBAU, 0x7888F078U, 0x256F4A25U, 0x2E725C2EU, 0x1C24381CU, 0xA6F157A6U, 0xB4C773B4U, 0xC65197C6U, 
    0xE823CBE8U, 0xDD7CA1DDU, 0x749CE874U, 0x1F213E1FU, 0x4BDD964BU, 0xBDDC61BDU, 0x8B860D8BU, 0x8A850F8AU, 
    0x7090E070U, 0x3E427C3EU, 0xB5C471B5U, 0x66AACC66U, 0x48D89048U, 0x03050603U, 0xF601F7F6U, 0x0E121C0EU, 
    0x61A3C261U, 0x355F6A35U, 0x57F9AE57U, 0xB9D069B9U, 0x86911786U, 0xC15899C1U, 0x1D273A1DU, 0x9EB9279EU, 
    0xE138D9E1U, 0xF813EBF8U, 0x98B32B98U, 0x11332211U, 0x69BBD269U, 0xD970A9D9U, 0x8E89078EU, 0x94A73394U, 
    0x9BB62D9BU, 0x1E223C1EU, 0x87921587U, 0xE920C9E9U, 0xCE4987CEU, 0x55FFAA55U, 0x28785028U, 0xDF7AA5DFU, 
    0x8C8F038CU, 0xA1F859A1U, 0x89800989U, 0x0D171A0DU, 0xBFDA65BFU, 0xE631D7E6U, 0x42C68442U, 0x68B8D068U, 
    0x41C38241U, 0x99B02999U, 0x2D775A2DU, 0x0F111E0FU, 0xB0CB7BB0U, 0x54FCA854U, 0xBBD66DBBU, 0x163A2C16U
};

__device__ __constant__ unsigned int TS3[256] = {
    0x6363A5C6U, 0x7C7C84F8U, 0x777799EEU, 0x7B7B8DF6U, 0xF2F20DFFU, 0x6B6BBDD6U, 0x6F6FB1DEU, 0xC5C55491U, 
    0x30305060U, 0x01010302U, 0x6767A9CEU, 0x2B2B7D56U, 0xFEFE19E7U, 0xD7D762B5U, 0xABABE64DU, 0x76769AECU, 
    0xCACA458FU, 0x82829D1FU, 0xC9C94089U, 0x7D7D87FAU, 0xFAFA15EFU, 0x5959EBB2U, 0x4747C98EU, 0xF0F00BFBU, 
    0xADADEC41U, 0xD4D467B3U, 0xA2A2FD5FU, 0xAFAFEA45U, 0x9C9CBF23U, 0xA4A4F753U, 0x727296E4U, 0xC0C05B9BU, 
    0xB7B7C275U, 0xFDFD1CE1U, 0x9393AE3DU, 0x26266A4CU, 0x36365A6CU, 0x3F3F417EU, 0xF7F702F5U, 0xCCCC4F83U, 
    0x34345C68U, 0xA5A5F451U, 0xE5E534D1U, 0xF1F108F9U, 0x717193E2U, 0xD8D873ABU, 0x31315362U, 0x15153F2AU, 
    0x04040C08U, 0xC7C75295U, 0x23236546U, 0xC3C35E9DU, 0x18182830U, 0x9696A137U, 0x05050F0AU, 0x9A9AB52FU, 
    0x0707090EU, 0x12123624U, 0x80809B1BU, 0xE2E23DDFU, 0xEBEB26CDU, 0x2727694EU, 0xB2B2CD7FU, 0x75759FEAU, 
    0x09091B12U, 0x83839E1DU, 0x2C2C7458U, 0x1A1A2E34U, 0x1B1B2D36U, 0x6E6EB2DCU, 0x5A5AEEB4U, 0xA0A0FB5BU, 
    0x5252F6A4U, 0x3B3B4D76U, 0xD6D661B7U, 0xB3B3CE7DU, 0x29297B52U, 0xE3E33EDDU, 0x2F2F715EU, 0x84849713U, 
    0x5353F5A6U, 0xD1D168B9U, 0x00000000U, 0xEDED2CC1U, 0x20206040U, 0xFCFC1FE3U, 0xB1B1C879U, 0x5B5BEDB6U, 
    0x6A6ABED4U, 0xCBCB468DU, 0xBEBED967U, 0x39394B72U, 0x4A4ADE94U, 0x4C4CD498U, 0x5858E8B0U, 0xCFCF4A85U, 
    0xD0D06BBBU, 0xEFEF2AC5U, 0xAAAAE54FU, 0xFBFB16EDU, 0x4343C586U, 0x4D4DD79AU, 0x33335566U, 0x85859411U, 
    0x4545CF8AU, 0xF9F910E9U, 0x02020604U, 0x7F7F81FEU, 0x5050F0A0U, 0x3C3C4478U, 0x9F9FBA25U, 0xA8A8E34BU, 
    0x5151F3A2U, 0xA3A3FE5DU, 0x4040C080U, 0x8F8F8A05U, 0x9292AD3FU, 0x9D9DBC21U, 0x38384870U, 0xF5F504F1U, 
    0xBCBCDF63U, 0xB6B6C177U, 0xDADA75AFU, 0x21216342U, 0x10103020U, 0xFFFF1AE5U, 0xF3F30EFDU, 0xD2D26DBFU, 
    0xCDCD4C81U, 0x0C0C1418U, 0x13133526U, 0xECEC2FC3U, 0x5F5FE1BEU, 0x9797A235U, 0x4444CC88U, 0x1717392EU, 
    0xC4C45793U, 0xA7A7F255U, 0x7E7E82FCU, 0x3D3D477AU, 0x6464ACC8U, 0x5D5DE7BAU, 0x19192B32U, 0x737395E6U, 
    0x6060A0C0U, 0x81819819U, 0x4F4FD19EU, 0xDCDC7FA3U, 0x22226644U, 0x2A2A7E54U, 0x9090AB3BU, 0x8888830BU, 
    0x4646CA8CU, 0xEEEE29C7U, 0xB8B8D36BU, 0x14143C28U, 0xDEDE79A7U, 0x5E5EE2BCU, 0x0B0B1D16U, 0xDBDB76ADU, 
    0xE0E03BDBU, 0x32325664U, 0x3A3A4E74U, 0x0A0A1E14U, 0x4949DB92U, 0x06060A0CU, 0x24246C48U, 0x5C5CE4B8U, 
    0xC2C25D9FU, 0xD3D36EBDU, 0xACACEF43U, 0x6262A6C4U, 0x9191A839U, 0x9595A431U, 0xE4E437D3U, 0x79798BF2U, 
    0xE7E732D5U, 0xC8C8438BU, 0x3737596EU, 0x6D6DB7DAU, 0x8D8D8C01U, 0xD5D564B1U, 0x4E4ED29CU, 0xA9A9E049U, 
    0x6C6CB4D8U, 0x5656FAACU, 0xF4F407F3U, 0xEAEA25CFU, 0x6565AFCAU, 0x7A7A8EF4U, 0xAEAEE947U, 0x08081810U, 
    0xBABAD56FU, 0x787888F0U, 0x25256F4AU, 0x2E2E725CU, 0x1C1C2438U, 0xA6A6F157U, 0xB4B4C773U, 0xC6C65197U, 
    0xE8E823CBU, 0xDDDD7CA1U, 0x74749CE8U, 0x1F1F213EU, 0x4B4BDD96U, 0xBDBDDC61U, 0x8B8B860DU, 0x8A8A850FU, 
    0x707090E0U, 0x3E3E427CU, 0xB5B5C471U, 0x6666AACCU, 0x4848D890U, 0x03030506U, 0xF6F601F7U, 0x0E0E121CU, 
    0x6161A3C2U, 0x35355F6AU, 0x5757F9AEU, 0xB9B9D069U, 0x86869117U, 0xC1C15899U, 0x1D1D273AU, 0x9E9EB927U, 
    0xE1E138D9U, 0xF8F813EBU, 0x9898B32BU, 0x11113322U, 0x6969BBD2U, 0xD9D970A9U, 0x8E8E8907U, 0x9494A733U, 
    0x9B9BB62DU, 0x1E1E223CU, 0x87879215U, 0xE9E920C9U, 0xCECE4987U, 0x5555FFAAU, 0x28287850U, 0xDFDF7AA5U, 
    0x8C8C8F03U, 0xA1A1F859U, 0x89898009U, 0x0D0D171AU, 0xBFBFDA65U, 0xE6E631D7U, 0x4242C684U, 0x6868B8D0U, 
    0x4141C382U, 0x9999B029U, 0x2D2D775AU, 0x0F0F111EU, 0xB0B0CB7BU, 0x5454FCA8U, 0xBBBBD66DU, 0x16163A2CU
};

__device__ unsigned char get_sbox(unsigned char b) {
    return (TS0[b] >> 16) & 0xFF;
}

__device__ void shift_rows(unsigned char *state) {
    unsigned char t;
    t = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
    t = state[2]; state[2] = state[10]; state[10] = t; t = state[6]; state[6] = state[14]; state[14] = t;
    t = state[3]; state[3] = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = t;
}

__device__ void aes256_key_expansion(const unsigned char *key, unsigned char *w) {
    unsigned int *ww = (unsigned int *)w;
    for (int i = 0; i < 8; i++) ww[i] = ((unsigned int *)key)[i];
    for (int i = 8; i < 60; i++) {
        unsigned int temp = ww[i - 1];
        if (i % 8 == 0) {
            temp = (temp << 8) | (temp >> 24);
            temp = get_sbox(temp) | (get_sbox(temp >> 8) << 8) | (get_sbox(temp >> 16) << 16) | (get_sbox(temp >> 24) << 24);
            temp ^= rcon[i / 8];
        } else if (i % 8 == 4) {
            temp = get_sbox(temp) | (get_sbox(temp >> 8) << 8) | (get_sbox(temp >> 16) << 16) | (get_sbox(temp >> 24) << 24);
        }
        ww[i] = ww[i - 8] ^ temp;
    }
}

__device__ void add_round_key(unsigned char* state, const unsigned char* round_key) {
    for (int i = 0; i < 16; i++) {
        state[i] ^= round_key[i];
    }
}

__device__ void aes_encrypt_block(const unsigned char *in, unsigned char *out, const unsigned char *key) {
    unsigned char state[16];
    memcpy(state, in, 16);
    unsigned char rk[240];
    aes256_key_expansion(key, rk);
    add_round_key(state, rk);
    for (int r = 1; r < 14; r++) {
        unsigned int t0 = TS0[state[0]] ^ TS1[state[5]] ^ TS2[state[10]] ^ TS3[state[15]] ^ ((unsigned int *)rk)[r * 4];
        unsigned int t1 = TS0[state[1]] ^ TS1[state[6]] ^ TS2[state[11]] ^ TS3[state[12]] ^ ((unsigned int *)rk)[r * 4 + 1];
        unsigned int t2 = TS0[state[2]] ^ TS1[state[7]] ^ TS2[state[8]] ^ TS3[state[13]] ^ ((unsigned int *)rk)[r * 4 + 2];
        unsigned int t3 = TS0[state[3]] ^ TS1[state[4]] ^ TS2[state[9]] ^ TS3[state[14]] ^ ((unsigned int *)rk)[r * 4 + 3];
        *(unsigned int *)(state + 0) = t0;
        *(unsigned int *)(state + 4) = t1;
        *(unsigned int *)(state + 8) = t2;
        *(unsigned int *)(state + 12) = t3;
    }
    for (int i = 0; i < 16; i++) state[i] = get_sbox(state[i]);
    shift_rows(state);
    add_round_key(state, rk + 224);
    memcpy(out, state, 16);
}

__device__ void sha256_init(uint32_t *h) {
    h[0] = 0x6a09e667; h[1] = 0xbb67ae85; h[2] = 0x3c6ef372; h[3] = 0xa54ff53a;
    h[4] = 0x510e527f; h[5] = 0x9b05688c; h[6] = 0x1f83d9ab; h[7] = 0x5be0cd19;
}

__device__ void sha256_transform(const unsigned char *data, uint32_t *h) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = (data[i * 4] << 24) | (data[i * 4 + 1] << 16) | (data[i * 4 + 2] << 8) | data[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = (w[i - 15] >> 7 | w[i - 15] << 25) ^ (w[i - 15] >> 18 | w[i - 15] << 14) ^ (w[i - 15] >> 3);
        uint32_t s1 = (w[i - 2] >> 17 | w[i - 2] << 15) ^ (w[i - 2] >> 19 | w[i - 2] << 13) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
        uint32_t s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + maj;
        hh = g; g = f; f = e; e = d + temp1; d = c; c = b; b = a; a = temp1 + temp2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

__device__ void sha256(const unsigned char *data, size_t len, unsigned char *hash) {
    uint32_t h[8];
    sha256_init(h);
    size_t off = 0;
    while (len >= 64) {
        sha256_transform(data + off, h);
        off += 64; len -= 64;
    }
    unsigned char buf[64];
    memcpy(buf, data + off, len);
    buf[len] = 0x80;
    if (len > 55) {
        memset(buf + len + 1, 0, 63 - len);
        sha256_transform(buf, h);
        memset(buf, 0, 64);
    } else {
        memset(buf + len + 1, 0, 55 - len);
    }
    uint64_t bitlen = (off + len) * 8;
    buf[56] = bitlen >> 56; buf[57] = bitlen >> 48; buf[58] = bitlen >> 40; buf[59] = bitlen >> 32;
    buf[60] = bitlen >> 24; buf[61] = bitlen >> 16; buf[62] = bitlen >> 8; buf[63] = bitlen;
    sha256_transform(buf, h);
    for (int i = 0; i < 8; i++) {
        hash[i * 4] = h[i] >> 24; hash[i * 4 + 1] = h[i] >> 16;
        hash[i * 4 + 2] = h[i] >> 8; hash[i * 4 + 3] = h[i];
    }
}

__device__ void hmac_sha256(const unsigned char *key, size_t keylen, const unsigned char *msg, size_t msglen, unsigned char *out) {
    unsigned char kpad[64];
    memset(kpad, 0, 64);
    if (keylen > 64) {
        sha256(key, keylen, kpad);
    } else {
        memcpy(kpad, key, keylen);
    }
    unsigned char inner[64 + 1024];
    for (int i = 0; i < 64; i++) inner[i] = kpad[i] ^ 0x36;
    memcpy(inner + 64, msg, msglen);
    unsigned char temp[32];
    sha256(inner, 64 + msglen, temp);
    unsigned char outer[64 + 32];
    for (int i = 0; i < 64; i++) outer[i] = kpad[i] ^ 0x5c;
    memcpy(outer + 64, temp, 32);
    sha256(outer, 64 + 32, out);
}

__device__ void pbkdf2_hmac_sha256(const unsigned char *pass, size_t passlen, const unsigned char *salt, size_t saltlen, int iterations, unsigned char *dk, size_t dklen) {
    unsigned char tmp[32];
    unsigned char buf[64 + 4];
    memcpy(buf, salt, saltlen);
    int block = 1;
    size_t off = 0;
    while (off < dklen) {
        buf[saltlen] = block >> 24; buf[saltlen + 1] = block >> 16;
        buf[saltlen + 2] = block >> 8; buf[saltlen + 3] = block;
        hmac_sha256(pass, passlen, buf, saltlen + 4, tmp);
        unsigned char u[32];
        memcpy(u, tmp, 32);
        for (int i = 1; i < iterations; i++) {
            hmac_sha256(pass, passlen, u, 32, u);
            for (int j = 0; j < 32; j++) tmp[j] ^= u[j];
        }
        size_t cp = (dklen - off > 32) ? 32 : dklen - off;
        memcpy(dk + off, tmp, cp);
        off += cp;
        block++;
    }
}

__device__ bool aes_ccm_decrypt(const unsigned char *encrypted, int encrypted_len, const unsigned char *key, const unsigned char *nonce, int nonce_len, unsigned char *decrypted) {
    const int TAG_LEN = 12;
    const int AES_BLOCK_SIZE = 16;
    int ciphertext_len = encrypted_len - TAG_LEN;
    if (ciphertext_len <= 0 || nonce_len != 12) return false;
    int L = 15 - nonce_len;
    unsigned char ciphertext[48];
    unsigned char tag[12];
    memcpy(ciphertext, encrypted, ciphertext_len);
    memcpy(tag, encrypted + ciphertext_len, TAG_LEN);
    unsigned char counter[16];
    counter[0] = L - 1;
    memcpy(counter + 1, nonce, nonce_len);
    memset(counter + 1 + nonce_len, 0, L);
    unsigned char key_stream_block[16];
    int ctr = 1;
    for (int i = 0; i < ciphertext_len; i += AES_BLOCK_SIZE) {
        unsigned char ctr_counter[16];
        memcpy(ctr_counter, counter, 16);
        unsigned char c_val = ctr;
        for (int j = L - 1; j >= 0; j--) {
            ctr_counter[15 - j] = c_val & 0xFF;
            c_val >>= 8;
        }
        aes_encrypt_block(ctr_counter, key_stream_block, key);
        int cp = (AES_BLOCK_SIZE < ciphertext_len - i ? AES_BLOCK_SIZE : ciphertext_len - i);
        for (int j = 0; j < cp; j++) {
            decrypted[i + j] = ciphertext[i + j] ^ key_stream_block[j];
        }
        ctr++;
    }
    int flags = ((TAG_LEN - 2) / 2 << 3) | (L - 1);
    unsigned char B0[16];
    B0[0] = flags;
    memcpy(B0 + 1, nonce, nonce_len);
    unsigned char m_len = ciphertext_len;
    for (int j = L - 1; j >= 0; j--) {
        B0[15 - j] = m_len & 0xFF;
        m_len >>= 8;
    }
    unsigned char mac[16];
    aes_encrypt_block(B0, mac, key);
    for (int i = 0; i < ciphertext_len; i += AES_BLOCK_SIZE) {
        unsigned char block[16] = {0};
        int cp = (AES_BLOCK_SIZE < ciphertext_len - i ? AES_BLOCK_SIZE : ciphertext_len - i);
        memcpy(block, decrypted + i, cp);
        for (int j = 0; j < AES_BLOCK_SIZE; j++) block[j] ^= mac[j];
        aes_encrypt_block(block, mac, key);
    }
    unsigned char counter0[16];
    counter0[0] = L - 1;
    memcpy(counter0 + 1, nonce, nonce_len);
    memset(counter0 + 1 + nonce_len, 0, L);
    unsigned char S0[16];
    aes_encrypt_block(counter0, S0, key);
    for (int i = 0; i < TAG_LEN; i++) {
        if ((S0[i] ^ mac[i]) != tag[i]) return false;
    }
    return true;
}

__device__ bool verify_decrypted(const unsigned char* decrypted, size_t len) {
    if (len < 4) return false;
    return (decrypted[0] == 'V' && decrypted[1] == 'M' && decrypted[2] == 'K' && decrypted[3] == 0);
}

__device__ void recovery_password_to_key(const unsigned char *password, const unsigned char *salt, int salt_len, int iterations, unsigned char *key) {
    pbkdf2_hmac_sha256(password, 110, salt, salt_len, iterations, key, 32);
}

__device__ void generate_password(unsigned long long index, unsigned char* password) {
    const unsigned long long base = 90909ULL;
    const int pow10[] = {1, 10, 100, 1000, 10000, 100000};
    int pos = 0;
    for (int i = 0; i < 8; i++) {
        unsigned long long k = index % base;
        index /= base;
        int block_value = 11 * k;
        for (int j = 5; j >= 0; j--) {
            int digit = (block_value / pow10[j]) % 10;
            password[pos] = '0' + digit;
            password[pos + 1] = 0;
            pos += 2;
        }
        if (i < 7) {
            password[pos] = '-';
            password[pos + 1] = 0;
            pos += 2;
        }
    }
}

__global__ void brute_force_kernel(
    unsigned char* salt, int salt_len, int iterations,
    unsigned char* nonce, int nonce_len,
    unsigned char* encrypted_data, int encrypted_len,
    unsigned long long start_index, int* found_flag,
    unsigned char* result_password) {

    unsigned long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long long index = start_index + tid;

    unsigned char password[110];
    generate_password(index, password);

    unsigned char derived_key[32];
    recovery_password_to_key(password, salt, salt_len, iterations, derived_key);

    unsigned char decrypted[48];
    bool success = aes_ccm_decrypt(encrypted_data, encrypted_len, derived_key, nonce, nonce_len, decrypted);
    if (success && verify_decrypted(decrypted, 48)) {
        if (atomicCAS(found_flag, 0, 1) == 0) {
            memcpy(result_password, password, 110);
        }
    }
}

struct HashParams {
    std::vector<unsigned char> salt;
    int iterations;
    std::vector<unsigned char> iv;
    std::vector<unsigned char> encrypted_data;
};

std::vector<unsigned char> hex_to_bytes(const std::string& hex) {
    std::vector<unsigned char> bytes;
    if (hex.length() % 2 != 0) {
        throw std::runtime_error("Hex string length must be even");
    }
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byte_str = hex.substr(i, 2);
        unsigned char byte = static_cast<unsigned char>(std::stoi(byte_str, nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

HashParams parse_hash(const std::string& hash) {
    HashParams params;
    std::vector<std::string> fields;
    std::stringstream ss(hash);
    std::string field;
    while (std::getline(ss, field, '$')) {
        if (!field.empty()) {
            fields.push_back(field);
        }
    }
    if (fields.size() < 9 || fields[0] != "bitlocker") {
        throw std::runtime_error("Invalid BitLocker hash format");
    }
    try {
        size_t idx = 1;
        idx++;
        int salt_len = std::stoi(fields[idx++]);
        std::string salt_hex = fields[idx++];
        if (salt_hex.length() != static_cast<size_t>(salt_len) * 2) {
            throw std::runtime_error("Salt length mismatch");
        }
        params.salt = hex_to_bytes(salt_hex);
        params.iterations = std::stoi(fields[idx++]);
        int iv_len = std::stoi(fields[idx++]);
        std::string iv_hex = fields[idx++];
        if (iv_hex.length() != static_cast<size_t>(iv_len) * 2) {
            throw std::runtime_error("IV length mismatch");
        }
        params.iv = hex_to_bytes(iv_hex);
        int encrypted_len = std::stoi(fields[idx++]);
        std::string encrypted_hex = fields[idx++];
        if (encrypted_hex.length() != static_cast<size_t>(encrypted_len) * 2) {
            throw std::runtime_error("Encrypted data length mismatch");
        }
        params.encrypted_data = hex_to_bytes(encrypted_hex);
    } catch (const std::exception& e) {
        throw std::runtime_error("Failed to parse hash: " + std::string(e.what()));
    }
    return params;
}

bool running = true;
unsigned long long total_candidates_tested = 0;

void display_progress() {
    while (running) {
        std::cout << "Total candidates tested: " << total_candidates_tested << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}

void display_gpu_utilization() {
    while (running) {
        std::cout << "GPU Utilization: ";
        system("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits");
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }
}

int main(int argc, char* argv[]) {
    std::string hash_str;
    std::string input_file;
    std::string output_file = "found.txt";
    int threads_per_block = 256;
    int blocks = 256;

    int opt;
    while ((opt = getopt(argc, argv, "hf:t:b:o:")) != -1) {
        switch (opt) {
            case 'h':
                std::cout << "Usage: " << argv[0] << " [options] [hash]" << std::endl;
                std::cout << "Options:" << std::endl;
                std::cout << "  -h        Show this help message and exit." << std::endl;
                std::cout << "  -f <file> Input file containing the BitLocker hash." << std::endl;
                std::cout << "  -t <num>  Set the number of threads per block (default: 256)." << std::endl;
                std::cout << "  -b <num>  Set the number of blocks (default: 256)." << std::endl;
                std::cout << "  -o <file> Output the found recovery key to the specified file (default: found.txt in current directory)." << std::endl;
                return 0;
            case 'f':
                input_file = optarg;
                break;
            case 't':
                threads_per_block = std::atoi(optarg);
                break;
            case 'b':
                blocks = std::atoi(optarg);
                break;
            case 'o':
                output_file = optarg;
                break;
            default:
                std::cerr << "Unknown option: -" << char(optopt) << std::endl;
                return 1;
        }
    }

    if (!input_file.empty()) {
        std::ifstream ifs(input_file);
        if (!ifs) {
            std::cerr << "Error opening input file: " << input_file << std::endl;
            return 1;
        }
        std::stringstream ss;
        ss << ifs.rdbuf();
        hash_str = ss.str();
        // Trim trailing newline if present
        if (!hash_str.empty() && hash_str.back() == '\n') {
            hash_str.pop_back();
        }
    } else if (optind < argc) {
        hash_str = argv[optind];
    } else {
        std::cerr << "No hash provided. Use -h for help." << std::endl;
        return 1;
    }

    try {
        HashParams params = parse_hash(hash_str);

        unsigned char *d_salt, *d_nonce, *d_encrypted, *d_result_password;
        int *d_found_flag;
        CUDA_CHECK(cudaMalloc(&d_salt, params.salt.size()));
        CUDA_CHECK(cudaMalloc(&d_nonce, params.iv.size()));
        CUDA_CHECK(cudaMalloc(&d_encrypted, params.encrypted_data.size()));
        CUDA_CHECK(cudaMalloc(&d_found_flag, sizeof(int)));
        CUDA_CHECK(cudaMalloc(&d_result_password, 110));

        CUDA_CHECK(cudaMemcpy(d_salt, params.salt.data(), params.salt.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_nonce, params.iv.data(), params.iv.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_encrypted, params.encrypted_data.data(), params.encrypted_data.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemset(d_found_flag, 0, sizeof(int)));

        unsigned long long candidates_per_launch = static_cast<unsigned long long>(blocks) * threads_per_block;

        std::thread progress_thread(display_progress);
        std::thread gpu_thread(display_gpu_utilization);

        unsigned long long max_index = 1ULL;
        for (int i = 0; i < 8; i++) max_index *= 90909ULL;

        for (unsigned long long start = 0; start < max_index; start += candidates_per_launch) {
            brute_force_kernel<<<blocks, threads_per_block>>>(
                d_salt, params.salt.size(), params.iterations,
                d_nonce, params.iv.size(),
                d_encrypted, params.encrypted_data.size(),
                start, d_found_flag, d_result_password
            );
            cudaDeviceSynchronize();

            total_candidates_tested += candidates_per_launch;

            int found;
            CUDA_CHECK(cudaMemcpy(&found, d_found_flag, sizeof(int), cudaMemcpyDeviceToHost));
            if (found) {
                unsigned char result[110];
                CUDA_CHECK(cudaMemcpy(result, d_result_password, 110, cudaMemcpyDeviceToHost));
                std::ofstream ofs(output_file);
                if (!ofs) {
                    std::cerr << "Error opening output file: " << output_file << std::endl;
                    break;
                }
                ofs << "Password found: ";
                for (int i = 0; i < 110; i += 2) {
                    ofs << result[i];
                }
                ofs << std::endl;
                std::cout << "Password found and written to " << output_file << std::endl;
                break;
            }
        }

        running = false;
        progress_thread.join();
        gpu_thread.join();

        cudaFree(d_salt);
        cudaFree(d_nonce);
        cudaFree(d_encrypted);
        cudaFree(d_found_flag);
        cudaFree(d_result_password);
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
